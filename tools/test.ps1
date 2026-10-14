#Requires -Version 7.4
<#
.SYNOPSIS
    Teste le harness : génère un projet de chaque type dans un dossier temporaire,
    puis lance le doctor et les autotests Pester dans chacun.

.DESCRIPTION
    Utilise l'état courant du dépôt, modifications non commitées comprises
    (copier --vcs-ref HEAD). Code de sortie 1 au moindre échec.

.PARAMETER Scenario
    Scénarios à générer (par défaut : tous) :
      sandbox : kind=sandbox, modules react + dotnet + game ;
      python  : kind=app, modules react + python ;
      root    : kind=root, aucun module ;
      invalid : combinaison refusée (game sans dotnet) : Copier doit échouer.

.PARAMETER Keep
    Conserve les projets générés pour les inspecter.
#>
[CmdletBinding()]
param(
    [ValidateSet('sandbox', 'python', 'root', 'invalid', 'invalid2')]
    [string[]] $Scenario = @('sandbox', 'python', 'root', 'invalid', 'invalid2'),
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$work = Join-Path ([IO.Path]::GetTempPath()) "harness-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$failed = 0
# Copier (Python) écrit en UTF-8 : sans ça, ses messages accentués s'affichent mal.
$env:PYTHONUTF8 = '1'
# Pas d'installation de plugins pour des projets jetables (registre de Claude Code).
$env:HARNESS_SKIP_PLUGINS = '1'

$scenarios = @{
    sandbox = @{ Kind = 'sandbox'; Modules = '["react", "dotnet", "game"]' }
    python  = @{ Kind = 'app';     Modules = '["react", "python"]' }
    root    = @{ Kind = 'root';    Modules = '[]' }
    invalid = @{ Kind = 'app';     Modules = '["react", "game"]'; MustFail = 'game s''utilise avec dotnet et react' }
    invalid2 = @{ Kind = 'app';    Modules = '["react", "dotnet", "python"]'; MustFail = 'un seul backend' }
}

foreach ($name in $Scenario) {
    $s = $scenarios[$name]
    $k = $s.Kind
    # Le dossier racine s'appelle `services` pour kind=root : claudeMdExcludes en dépend.
    $dest = Join-Path $work $name ($k -eq 'root' ? 'services' : "test-$name")
    New-Item -ItemType Directory -Force $dest | Out-Null
    git -C $dest init -q -b main
    Write-Host "`n=== $name (kind=$k, modules=$($s.Modules)) → $dest" -ForegroundColor Cyan

    $copierOutput = copier copy --quiet --trust --defaults --vcs-ref HEAD --data kind=$k --data "modules=$($s.Modules)" --data "description=Projet de test ($k)" $repo $dest 2>&1 |
        Where-Object { $_ -notmatch 'DirtyLocalWarning|dirty|^\s*warn\(' }
    # Un refus attendu n'affiche que sa raison, pas la trace Python complète.
    if ($s.MustFail) { $copierOutput | Select-Object -Last 1 | Out-Host } else { $copierOutput | Out-Host }
    if ($s.MustFail) {
        # Le refus doit venir du validateur, avec la bonne raison : pas de n'importe quelle erreur.
        if ($LASTEXITCODE -eq 0) { Write-Host 'combinaison invalide acceptée par Copier' -ForegroundColor Red; $failed++ }
        elseif (($copierOutput | Out-String) -notmatch [regex]::Escape($s.MustFail)) { Write-Host "refus pour une autre raison que « $($s.MustFail) »" -ForegroundColor Red; $failed++ }
        else { Write-Host 'combinaison invalide refusée par Copier, pour la bonne raison : OK' }
        continue
    }
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
