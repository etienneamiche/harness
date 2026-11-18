#Requires -Version 7.4

<#
.SYNOPSIS
    Lint du code d'infra sur les fichiers modifiés. Lancé en fin de tour par stop-checks
    (module.json → stopChecks), et à la main.

.DESCRIPTION
    Chaque outil ne lit que les fichiers modifiés selon `git status` (ou ceux de -Path) :
    une dette ancienne ne bloque pas chaque fin de tour. Un outil absent est une erreur, avec
    la façon de l'installer : le lint ne passe jamais pour vert sans avoir tourné.
    Code de sortie 0 si tout passe, 1 sinon.

.PARAMETER Tool
    tofu         : `tofu fmt -check`, `tofu validate` et `tflint`, dans chaque dossier de tofu/
                   qui contient un .tf ou .tofu modifié. `validate` demande les providers et
                   modules installés par un `tofu init` : le lint ne le lance pas (il télécharge),
                   il dit de le faire.
    kubeconform  : les manifestes modifiés sous clusters/ (fichiers avec une clé `kind:`), hors
                   *.sops.yaml et templates de chart. Schémas des CRD lus dans le catalogue
                   datree, schémas introuvables ignorés.
    yamllint     : tout YAML modifié, hors *.sops.yaml et templates de chart. Config du dépôt
                   (.yamllint, .yamllint.yaml, .yamllint.yml), sinon une config compatible
                   avec ansible-lint.
    ansible-lint : le YAML modifié sous ansible/, hors *.sops.yaml, dans WSL (distribution
                   HARNESS_WSL_DISTRO, Ubuntu par défaut).

.PARAMETER Path
    Fichiers à lire, relatifs à la racine du dépôt, au lieu des fichiers modifiés.

.PARAMETER Missing
    Ne lit rien : renvoie les outils absents ({ Name; Hint }), pour le doctor.

.EXAMPLE
    ./.harness/modules/infra/lint.ps1 tofu
    ./.harness/modules/infra/lint.ps1 yamllint -Path clusters/home/apps/blog/values.yaml
    ./.harness/modules/infra/lint.ps1 -Missing
#>
[CmdletBinding(DefaultParameterSetName = 'Lint')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Lint')]
    [ValidateSet('tofu', 'kubeconform', 'yamllint', 'ansible-lint')]
    [string] $Tool,

    [Parameter(ParameterSetName = 'Lint')]
    [string[]] $Path,

    [Parameter(Mandatory, ParameterSetName = 'Missing')]
    [switch] $Missing
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' '..')).Path
$distro = if ($env:HARNESS_WSL_DISTRO) { $env:HARNESS_WSL_DISTRO } else { 'Ubuntu' }
$setup = 'ou scripts/setup-workstation.ps1 -Role admin à la racine services'

# Outils de chaque lint, et comment les installer.
$tools = [ordered]@{
    tofu           = "winget install --id OpenTofu.Tofu, $setup"
    tflint         = "winget install --id TerraformLinters.tflint, $setup"
    kubeconform    = "winget install --id YannHamon.kubeconform, $setup"
    yamllint       = "uv tool install yamllint, $setup"
    'ansible-lint' = "wsl -d $distro --exec bash -lc 'uv tool install ansible-lint', $setup"
}
$needs = @{ tofu = 'tofu', 'tflint'; kubeconform = , 'kubeconform'; yamllint = , 'yamllint'; 'ansible-lint' = , 'ansible-lint' }

function Test-Tool([string] $Name) {
    if ($Name -ne 'ansible-lint') { return [bool] (Get-Command $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) }
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return $false }
    # --exec : sinon wsl.exe interprète lui-même les `$` de la commande.
    $env:WSL_UTF8 = '1'
    wsl -d $distro --exec bash -lc 'command -v ansible-lint' *> $null
    $LASTEXITCODE -eq 0
}

if ($Missing) {
    foreach ($name in $tools.Keys) { if (-not (Test-Tool $name)) { [pscustomobject]@{ Name = $name; Hint = $tools[$name] } } }
    return
}

# Fichiers modifiés (ajoutés, modifiés, renommés, non suivis), chemins avec des `/`.
function Get-ChangedFile {
    $entries = @((git -C $root status --porcelain=v1 -z --untracked-files=all 2>$null) -split "`0" | Where-Object { $_ })
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        # Un renommage ou une copie est suivi de l'ancien chemin : on le saute.
        if ($entry[0] -in 'R', 'C') { $i++ }
        $entry.Substring(3)
    }
}
$files = @(if ($Path) { $Path -replace '\\', '/' } else { Get-ChangedFile }) |
    Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf } |
    Sort-Object -Unique

$problems = [System.Collections.Generic.List[string]]::new()
foreach ($name in $needs[$Tool]) {
    if (-not (Test-Tool $name)) { $problems.Add("$name est introuvable, le lint n'a pas tourné : $($tools[$name]). Un outil tout juste installé n'est vu qu'après avoir rouvert le terminal ou Claude Code.") }
}

# Lance un outil depuis un dossier ; garde sa sortie s'il échoue.
function Invoke-Lint([string] $Label, [string] $Dir, [scriptblock] $Command) {
    Push-Location $Dir
    try { $output = & $Command 2>&1 | Out-String; $code = $LASTEXITCODE }
    finally { Pop-Location }
    if ($code -ne 0) { $problems.Add("$Label :`n$($output.Trim())") }
}

$secret = '(^|/)[^/]+\.sops\.ya?ml$'
$chartTemplate = '(^|/)templates/'
$yaml = '\.ya?ml$'

switch ($Tool) {
    'tofu' {
        $dirs = @($files | Where-Object { $_ -match '^tofu/.*\.(tf|tofu)$' } | ForEach-Object { $_ -replace '/[^/]+$' } | Sort-Object -Unique)
        foreach ($rel in $dirs) {
            $dir = Join-Path $root $rel
            if (Get-Command tofu -ErrorAction SilentlyContinue) {
                Invoke-Lint "tofu fmt ($rel, à corriger par tofu fmt)" $dir { tofu fmt -check -list=true -no-color }
                # validate a besoin des providers et modules installés par `tofu init` : on ne le
                # lance pas ici (téléchargements), on dit de le faire.
                Push-Location $dir
                try { $output = tofu validate -no-color 2>&1 | Out-String; $code = $LASTEXITCODE }
                finally { Pop-Location }
                if ($code -ne 0 -and $output -match '(tofu|terraform) init|not installed|Missing required provider|Inconsistent dependency lock') {
                    $problems.Add("tofu validate ($rel) n'a pas pu tourner : lancer une fois ``tofu init`` dans $rel, puis recommencer.`n$($output.Trim())")
                }
                elseif ($code -ne 0) { $problems.Add("tofu validate ($rel) :`n$($output.Trim())") }
            }
            if (Get-Command tflint -ErrorAction SilentlyContinue) { Invoke-Lint "tflint ($rel)" $dir { tflint --no-color } }
        }
    }
    'kubeconform' {
        $manifests = @($files | Where-Object {
            $_ -match "^clusters/.*$yaml" -and $_ -notmatch $secret -and $_ -notmatch $chartTemplate -and
            (Get-Content -LiteralPath (Join-Path $root $_) -Raw) -match '(?m)^kind:\s*\S'
        })
        if ($manifests -and (Get-Command kubeconform -ErrorAction SilentlyContinue)) {
            $cache = Join-Path ([IO.Path]::GetTempPath()) 'harness-kubeconform'
            New-Item -ItemType Directory -Force $cache | Out-Null
            $crds = 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
            Invoke-Lint 'kubeconform' $root { kubeconform -strict -summary -ignore-missing-schemas -schema-location default -schema-location $crds -cache $cache @manifests }
        }
    }
    'yamllint' {
        $targets = @($files | Where-Object { $_ -match $yaml -and $_ -notmatch $secret -and $_ -notmatch "^charts/.*$chartTemplate" })
        if ($targets -and (Get-Command yamllint -ErrorAction SilentlyContinue)) {
            $own = @('.yamllint', '.yamllint.yaml', '.yamllint.yml' | Where-Object { Test-Path (Join-Path $root $_) })
            # Sans config du dépôt : les règles que ansible-lint attend de yamllint.
            $config = if ($own) { @() } else {
                @('-d', '{extends: default, rules: {line-length: {max: 160}, document-start: disable, comments: {min-spaces-from-content: 1}, comments-indentation: false, braces: {max-spaces-inside: 1}, octal-values: {forbid-implicit-octal: true, forbid-explicit-octal: true}, truthy: {allowed-values: ["true", "false"], check-keys: false}}}')
            }
            Invoke-Lint 'yamllint' $root { yamllint -f parsable @config @targets }
        }
    }
    'ansible-lint' {
        $targets = @($files | Where-Object { $_ -match "^ansible/.*$yaml" -and $_ -notmatch $secret })
        if ($targets -and (Test-Tool 'ansible-lint')) {
            # "$@" : les chemins arrivent en arguments, jamais dans le texte de la commande.
            Invoke-Lint 'ansible-lint' $root { wsl -d $distro --cd $root --exec bash -lc 'ansible-lint --nocolor -q "$@"' ansible-lint @targets }
        }
    }
}

if ($problems.Count -gt 0) {
    $problems -join "`n`n" | Write-Output
    exit 1
}
