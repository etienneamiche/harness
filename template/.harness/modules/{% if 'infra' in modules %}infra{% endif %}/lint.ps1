#Requires -Version 7.4

<#
.SYNOPSIS
    Lint du code d'infra sur les fichiers modifiés. Lancé en fin de tour par stop-checks
    (module.json → stopChecks), et à la main.

.DESCRIPTION
    Chaque outil ne lit que les fichiers modifiés selon `git status` (ou ceux de -Path) :
    une dette ancienne ne bloque pas chaque fin de tour. Un outil absent est une erreur dès
    qu'il a un fichier à lire, avec la façon de l'installer : le lint ne passe jamais pour
    vert sans avoir tourné. Code de sortie 0 si tout passe, 1 sinon.

    Ne sont jamais lus : les fichiers protégés du harness et les fichiers de secrets
    (`protectedPaths` et `secretPaths` de harness.json), les *.sops.yaml et les templates
    (dossiers `templates/`). Une sortie d'OpenTofu ou de tflint qui cite un *.tfvars est
    masquée : ces fichiers contiennent des secrets en clair.

.PARAMETER Tool
    tofu         : `tofu fmt -check` sur les .tf et .tofu modifiés, puis `tofu validate` et
                   `tflint`, dans chaque dossier de tofu/ où un .tf ou .tofu a été modifié,
                   ajouté, supprimé ou renommé. `validate` demande les providers et modules
                   installés par un `tofu init` : le lint ne le lance pas (il télécharge), il
                   dit de le faire.
    kubeconform  : les manifestes modifiés sous clusters/ (fichiers avec une clé `kind:`).
                   Schémas des CRD lus dans le catalogue datree, schémas introuvables ignorés.
    yamllint     : tout YAML modifié. Config du dépôt (.yamllint, .yamllint.yaml,
                   .yamllint.yml), sinon une config compatible avec ansible-lint.
    ansible-lint : le YAML modifié sous ansible/, dans WSL (distribution HARNESS_WSL_DISTRO,
                   Ubuntu par défaut), sans téléchargement (`--offline`). Des collections ou
                   des rôles absents : il dit de lancer `ansible-galaxy`.

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
# --exec : sinon wsl.exe interprète lui-même les `$` de la commande.
$env:WSL_UTF8 = '1'

# Outils de chaque lint, et comment les installer.
$tools = [ordered]@{
    tofu           = "winget install --id OpenTofu.Tofu, $setup"
    tflint         = "winget install --id TerraformLinters.tflint, $setup"
    kubeconform    = "winget install --id YannHamon.kubeconform, $setup"
    yamllint       = "uv tool install yamllint, $setup"
    'ansible-lint' = "wsl -d $distro --exec bash -lc 'uv tool install ansible-lint', $setup"
}
$needs = @{ tofu = 'tofu', 'tflint'; kubeconform = , 'kubeconform'; yamllint = , 'yamllint'; 'ansible-lint' = , 'ansible-lint' }

# Ce qui manque pour lancer un outil, ou $null s'il est là.
function Get-ToolProblem([string] $Name) {
    if ($Name -ne 'ansible-lint') {
        if (Get-Command $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) { return $null }
        return $tools[$Name]
    }
    if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) { return "WSL est absent (wsl --install -d $distro), $setup" }
    $distros = @((wsl -l -q 2>$null) -split '\r?\n' | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($distros -notcontains $distro) {
        return "la distribution WSL « $distro » est absente (wsl --install -d $distro), ou HARNESS_WSL_DISTRO nomme une autre distribution ($($distros -join ', '))"
    }
    wsl -d $distro --exec bash -lc 'command -v ansible-lint' *> $null
    if ($LASTEXITCODE -eq 0) { return $null }
    $tools[$Name]
}

if ($Missing) {
    foreach ($name in $tools.Keys) { $hint = Get-ToolProblem $name; if ($hint) { [pscustomobject]@{ Name = $name; Hint = $hint } } }
    return
}

# Chemins modifiés selon git status, avec des `/` : ajoutés, modifiés, non suivis, mais aussi
# supprimés et anciens noms des renommages (un .tf supprimé change son dossier).
function Get-ChangedPath {
    $entries = @((git -C $root status --porcelain=v1 -z --untracked-files=all 2>$null) -split "`0" | Where-Object { $_ })
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $entry = $entries[$i]
        $entry.Substring(3)
        # Un renommage ou une copie est suivi de l'ancien chemin, sans code d'état.
        if ($entry[0] -in 'R', 'C') { $i++; $entries[$i] }
    }
}
$paths = @(if ($Path) { $Path -replace '\\', '/' } else { Get-ChangedPath }) | Sort-Object -Unique
# Fichiers encore présents : ceux que les outils liront.
$files = @($paths | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf })

$config = Get-Content (Join-Path $root '.harness' 'harness.json') -Raw | ConvertFrom-Json -AsHashtable
$never = @($config['protectedPaths']) + @($config['secretPaths']) + '(^|/)[^/]+\.sops\.ya?ml$', '(^|/)templates/'
function Test-Readable([string] $File) { -not ($never | Where-Object { $File -match $_ }) }
$yaml = '\.ya?ml$'
$tfSource = '^tofu/.*\.(tf|tofu)$'

# Ce que l'outil lira. Vide : rien à faire, même si l'outil est absent.
$targets = @(switch ($Tool) {
    'tofu' {
        # Dossiers touchés qui ont encore une config : chacun garde ses .tf modifiés pour fmt.
        $dirs = @($paths | Where-Object { $_ -match $tfSource } | ForEach-Object { $_ -replace '/[^/]+$' } | Sort-Object -Unique)
        foreach ($rel in $dirs) {
            $dir = Join-Path $root $rel
            if (-not (Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object Extension -in '.tf', '.tofu')) { continue }
            $changed = @($files | Where-Object { $_ -match $tfSource -and ($_ -replace '/[^/]+$') -eq $rel } | ForEach-Object { $_ -replace '^.*/' })
            [pscustomobject]@{ Dir = $rel; Files = $changed }
        }
    }
    'kubeconform' {
        $files | Where-Object {
            $_ -match "^clusters/.*$yaml" -and (Test-Readable $_) -and
            (Get-Content -LiteralPath (Join-Path $root $_) -Raw) -match '(?m)^kind:\s*\S'
        }
    }
    'yamllint' { $files | Where-Object { $_ -match $yaml -and (Test-Readable $_) } }
    'ansible-lint' { $files | Where-Object { $_ -match "^ansible/.*$yaml" -and (Test-Readable $_) } }
})
if (-not $targets) { exit 0 }

$problems = [System.Collections.Generic.List[string]]::new()
$present = @{}
foreach ($name in $needs[$Tool]) {
    $hint = Get-ToolProblem $name
    $present[$name] = -not $hint
    if ($hint) { $problems.Add("$name est introuvable, le lint n'a pas tourné : $hint. Un outil tout juste installé n'est vu qu'après avoir rouvert le terminal ou Claude Code.") }
}

# Lance un outil depuis un dossier ; rend sa sortie et son code.
function Invoke-Tool([string] $Dir, [scriptblock] $Command) {
    Push-Location $Dir
    try { $output = & $Command 2>&1 | Out-String; [pscustomobject]@{ Code = $LASTEXITCODE; Output = $output.Trim() } }
    finally { Pop-Location }
}
# Une sortie qui cite un *.tfvars peut en contenir une ligne, donc un secret : elle est masquée.
function Add-ToolProblem([string] $Label, [string] $Output, [string] $Dir) {
    if ($Output -match '\.tfvars') {
        $problems.Add("$Label : erreur dans un fichier *.tfvars de $Dir. Sortie masquée, ces fichiers contiennent des secrets en clair : l'utilisateur corrige le fichier et relance la commande lui-même.")
    }
    else { $problems.Add("$Label :`n$Output") }
}

switch ($Tool) {
    'tofu' {
        foreach ($t in $targets) {
            $dir = Join-Path $root $t.Dir
            if ($present.tofu) {
                $fmtFiles = $t.Files
                if ($fmtFiles) {
                    $r = Invoke-Tool $dir { tofu fmt -check -list=true -no-color @fmtFiles }
                    if ($r.Code -ne 0) { Add-ToolProblem "tofu fmt ($($t.Dir), à corriger par tofu fmt)" $r.Output $t.Dir }
                }
                # validate a besoin des providers et modules installés par `tofu init` : on ne le
                # lance pas ici (téléchargements), on dit de le faire.
                $r = Invoke-Tool $dir { tofu validate -no-color }
                if ($r.Code -ne 0 -and $r.Output -notmatch '\.tfvars' -and $r.Output -match '(tofu|terraform) init|not installed|Missing required provider|Inconsistent dependency lock') {
                    $problems.Add("tofu validate ($($t.Dir)) n'a pas pu tourner : lancer une fois ``tofu init`` dans $($t.Dir), puis recommencer.`n$($r.Output)")
                }
                elseif ($r.Code -ne 0) { Add-ToolProblem "tofu validate ($($t.Dir))" $r.Output $t.Dir }
            }
            if ($present.tflint) {
                $r = Invoke-Tool $dir { tflint --no-color }
                if ($r.Code -ne 0) { Add-ToolProblem "tflint ($($t.Dir))" $r.Output $t.Dir }
            }
        }
    }
    'kubeconform' {
        if ($present.kubeconform) {
            $cache = Join-Path ([IO.Path]::GetTempPath()) 'harness-kubeconform'
            New-Item -ItemType Directory -Force $cache | Out-Null
            $crds = 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
            $r = Invoke-Tool $root { kubeconform -strict -summary -ignore-missing-schemas -schema-location default -schema-location $crds -cache $cache @targets }
            if ($r.Code -ne 0) { $problems.Add("kubeconform :`n$($r.Output)") }
        }
    }
    'yamllint' {
        if ($present.yamllint) {
            $own = @('.yamllint', '.yamllint.yaml', '.yamllint.yml' | Where-Object { Test-Path (Join-Path $root $_) })
            # Sans config du dépôt : les règles que ansible-lint attend de yamllint. Les fins de
            # ligne sont laissées à .gitattributes, qui les normalise au commit.
            $yamlConfig = if ($own) { @() } else {
                @('-d', '{extends: default, rules: {line-length: {max: 160}, document-start: disable, new-lines: disable, comments: {min-spaces-from-content: 1}, comments-indentation: false, braces: {max-spaces-inside: 1}, octal-values: {forbid-implicit-octal: true, forbid-explicit-octal: true}, truthy: {allowed-values: ["true", "false"], check-keys: false}}}')
            }
            $r = Invoke-Tool $root { yamllint -f parsable @yamlConfig @targets }
            if ($r.Code -ne 0) { $problems.Add("yamllint :`n$($r.Output)") }
        }
    }
    'ansible-lint' {
        if ($present['ansible-lint']) {
            # "$@" : les chemins arrivent en arguments, jamais dans le texte de la commande.
            $r = Invoke-Tool $root { wsl -d $distro --cd $root --exec bash -lc 'ansible-lint --nocolor --offline -q "$@"' ansible-lint @targets }
            if ($r.Code -ne 0 -and $r.Output -match "couldn't resolve module|unknown-module|couldn't resolve role|the role '[^']+' was not found|unable to find .* collection|collection .* (was )?not found") {
                $problems.Add("ansible-lint : des collections ou des rôles manquent dans WSL. Lancer une fois, avec l'accord de l'utilisateur (infra-guard) : ``wsl -d $distro --cd <racine du dépôt> --exec bash -lc 'ansible-galaxy install -r ansible/requirements.yml'``, puis recommencer.`n$($r.Output)")
            }
            elseif ($r.Code -ne 0) { $problems.Add("ansible-lint :`n$($r.Output)") }
        }
    }
}

if ($problems.Count -gt 0) {
    $problems -join "`n`n" | Write-Output
    exit 1
}
