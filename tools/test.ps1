#Requires -Version 7.4
<#
.SYNOPSIS
    Teste le harness : génère un projet de chaque type dans un dossier temporaire,
    puis lance le doctor et les autotests Pester dans chacun.

.DESCRIPTION
    Utilise l'état courant du dépôt, modifications non commitées comprises
    (copier --vcs-ref HEAD). Code de sortie 1 au moindre échec.

.PARAMETER Kind
    Types de dépôt à générer. Par défaut : sandbox et root.

.PARAMETER Keep
    Conserve les projets générés pour les inspecter.
#>
[CmdletBinding()]
param(
    [string[]] $Kind = @('sandbox', 'root'),
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "harness-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$failed = 0
# Pas d'installation de plugins pour des projets jetables (registre de Claude Code).
$env:HARNESS_SKIP_PLUGINS = '1'

foreach ($k in $Kind) {
    # Le dossier racine s'appelle `services` pour kind=root : claudeMdExcludes en dépend.
    $dest = Join-Path $work $k ($k -eq 'root' ? 'services' : "test-$k")
    New-Item -ItemType Directory -Force $dest | Out-Null
    git -C $dest init -q -b main
    Write-Host "`n=== $k → $dest" -ForegroundColor Cyan

    copier copy --quiet --trust --defaults --vcs-ref HEAD --data kind=$k --data "description=Projet de test ($k)" $repo $dest 2>&1 |
        Where-Object { $_ -notmatch 'DirtyLocalWarning|dirty' } | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host "copier a échoué" -ForegroundColor Red; $failed++; continue }

    pwsh -NoProfile -File (Join-Path $dest '.harness' 'tools' 'doctor.ps1') -Deep -Offline
    if ($LASTEXITCODE -ne 0) { $failed++ }

    # Un projet tout juste généré doit se commiter : le hook pre-commit (gitleaks) ne doit
    # rien trouver dans les fichiers du harness eux-mêmes.
    git -C $dest add -A
    git -C $dest commit -q -m 'chore: harness (#0)' 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host 'le premier commit du projet généré est refusé' -ForegroundColor Red; $failed++ }
    else { Write-Host 'premier commit : OK (pre-commit passé)' }
}

if (-not $Keep) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Host "`nProjets conservés dans $work" }
Write-Host "`n$(if ($failed) { "ÉCHEC : $failed type(s) en erreur" } else { 'Tout est vert.' })" -ForegroundColor ($failed ? 'Red' : 'Green')
exit ([int]($failed -gt 0))
