#Requires -Version 7.4
# pre-commit : aucun secret ne part dans un commit, qu'il vienne d'un agent ou d'un humain.
# Échec fermé : sans gitleaks, le commit est refusé.

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = git rev-parse --show-toplevel

# 1. Noms de fichiers : un fichier secret ne s'indexe pas, même vide.
$config = Get-Content (Join-Path $root '.harness' 'harness.json') -Raw | ConvertFrom-Json -AsHashtable
$staged = @(git diff --cached --name-only --diff-filter=ACMR)
foreach ($file in $staged) {
    $isSecret = @($config.secretPaths | Where-Object { $file -match $_ }).Count -gt 0
    $isAllowed = @($config.secretPathsAllow | Where-Object { $file -match $_ }).Count -gt 0
    if ($isSecret -and -not $isAllowed) {
        Write-Host "harness/pre-commit : '$file' est un fichier secret, il ne doit pas être commité." -ForegroundColor Red
        Write-Host "  Le retirer de l'index : git restore --staged '$file'" -ForegroundColor Red
        exit 1
    }
}

# 2. Fichiers SOPS : chaque *.sops.yaml indexé est chiffré (`sops -e` oublié = secret en clair).
#    Un manifeste `Secret` de Kubernetes n'a que `data` et `stringData` chiffrés ; tout autre fichier
#    l'est en entier. Lecture ligne à ligne de la version indexée : chaque valeur doit être un ENC[…].
foreach ($file in $staged | Where-Object { $_ -match '(^|/)[^/]+\.sops\.ya?ml$' }) {
    $lines = @(git show ":$file") -replace '\r$', ''
    $sopsAt = [array]::IndexOf($lines, 'sops:')
    $body = if ($sopsAt -ge 0) { @($lines | Select-Object -First $sopsAt) } else { $lines }
    $hasMac = $sopsAt -ge 0 -and @($lines[$sopsAt..($lines.Count - 1)] | Where-Object { $_ -match '^\s+mac:\s*ENC\[' }).Count -gt 0
    $isK8sSecret = @($body | Where-Object { $_ -match '^kind:\s*Secret\s*$' }).Count -gt 0
    $section = ''
    $plain = @(foreach ($line in $body) {
        if ($line -match '^(\S[^:]*):') { $section = $Matches[1] }
        if ($isK8sSecret -and $section -notin 'data', 'stringData') { continue }
        if ($line -match '^\s*(#|$)' -or $line -match '^\s*---\s*$' -or $line -match '^\s*(-\s+)?ENC\[') { continue }
        # Une valeur : après `clé:` ou après `- `. `clé:` seul ouvre un bloc, sans valeur.
        $value = if ($line -match '^\s*(-\s+)?[^\s#:-][^:]*:\s*(.*)$') { $Matches[2] } elseif ($line -match '^\s*-\s+(.*)$') { $Matches[1] } else { $line.Trim() }
        if ($value -and $value -notmatch '^ENC\[') { $line }
    })
    if (-not $hasMac -or $plain) {
        $why = if (-not $hasMac) { 'il n''a pas de bloc sops: avec un mac chiffré' } else { "$($plain.Count) valeur(s) en clair" }
        Write-Host "harness/pre-commit : '$file' n'est pas chiffré ($why), commit refusé." -ForegroundColor Red
        Write-Host "  Le chiffrer d'abord : sops -e -i '$file'. Seuls les manifestes Secret de Kubernetes gardent leurs autres champs lisibles." -ForegroundColor Red
        exit 1
    }
}

# 3. Contenu : gitleaks sur les modifications indexées.
if (-not (Get-Command gitleaks -ErrorAction SilentlyContinue)) {
    Write-Host 'harness/pre-commit : gitleaks est introuvable, commit refusé (scripts/setup-workstation.ps1).' -ForegroundColor Red
    exit 1
}
gitleaks git --pre-commit --staged --redact --no-banner --log-level warn $root
if ($LASTEXITCODE -ne 0) {
    Write-Host 'harness/pre-commit : gitleaks a détecté un secret, commit refusé.' -ForegroundColor Red
    Write-Host "  Retirer le secret du fichier. S'il est réel, le révoquer : il a peut-être déjà fuité ailleurs." -ForegroundColor Red
    exit 1
}
exit 0
