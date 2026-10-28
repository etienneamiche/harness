#Requires -Version 7.4

<#
.SYNOPSIS
    Relève, en lecture seule, ce qui a gêné le travail dans les transcripts Claude Code du projet et dans les revues auditor.

.DESCRIPTION
    Lit les transcripts du projet (~/.claude/projects/<projet>/, sous-agents compris) sur une période, et rend un
    rapport Markdown :
      - les refus de hooks, groupés par règle et par raison ;
      - les commandes qui ont échoué au moins deux fois ;
      - les messages de l'utilisateur qui ressemblent à une correction (« non, … », « je t'ai dit… ») ;
      - les constats d'auditor (B1, I1, M1…) des dernières PR fusionnées, sauf avec -NoPrs.
    Ne modifie rien. Le tri des constats revient à la session : ce rapport n'est que la matière.

.PARAMETER Days
    Période couverte, en jours (14 par défaut).

.PARAMETER Path
    Dossier des transcripts. Par défaut, celui du projet : le chemin de la racine Git, chaque caractère
    non alphanumérique remplacé par « - », sous ~/.claude/projects.

.PARAMETER Prs
    Nombre de PR fusionnées à lire pour les constats d'auditor (10 par défaut).

.PARAMETER NoPrs
    Ne lit pas les PR (pas de gh, pas de réseau).

.EXAMPLE
    pwsh -NoProfile -File .claude/skills/retro/scripts/scan-transcripts.ps1 -Days 30
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 365)] [int] $Days = 14,
    [string] $Path,
    [ValidateRange(1, 50)] [int] $Prs = 10,
    [switch] $NoPrs
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = (git rev-parse --show-toplevel 2>$null)
if (-not $root) { $root = (Get-Location).Path }
$root = [IO.Path]::GetFullPath($root)
if (-not $Path) {
    $Path = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude' 'projects' ($root -replace '[^A-Za-z0-9]', '-')
}
$since = (Get-Date).AddDays(-$Days)

function Get-Text($content) {
    if ($content -is [string]) { return $content }
    (@($content) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
}
function Get-Short([string] $Text, [int] $Max = 140) {
    $one = ($Text -replace '\s+', ' ').Trim()
    if ($one.Length -le $Max) { $one } else { $one.Substring(0, $Max) + '…' }
}

$denials = @{}; $failures = @{}; $corrections = [System.Collections.Generic.List[object]]::new()
$sessions = [System.Collections.Generic.HashSet[string]]::new()
# Une correction commence par un refus ou un rappel ; les messages injectés (<…>) sont ignorés.
$correction = '^(non\b|nan\b|pas (ça|comme)|arr[eê]te|stop\b|je t[''\u2019]ai (déjà )?(dit|demandé)|j[''\u2019]ai (déjà )?dit|on avait dit|ne (fais|touche|mets|lance|modifie)|n[''\u2019]utilise pas|toujours\b|jamais\b)'

$files = @()
if (Test-Path $Path) { $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.jsonl' | Where-Object LastWriteTime -ge $since) }

foreach ($file in $files) {
    $calls = @{}
    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
        $o = try { $line | ConvertFrom-Json -Depth 20 } catch { $null }
        if (-not $o -or -not $o.message) { continue }
        if ($o.timestamp -and ([datetime] $o.timestamp) -lt $since) { continue }
        if ($o.sessionId) { [void] $sessions.Add($o.sessionId) }
        $content = $o.message.content
        if ($o.type -eq 'assistant') {
            foreach ($c in @($content) | Where-Object { $_.type -eq 'tool_use' }) {
                $what = if ($c.input.command) { $c.input.command } elseif ($c.input.file_path) { $c.input.file_path } else { '' }
                $calls[$c.id] = @{ Tool = $c.name; What = [string] $what }
            }
            continue
        }
        if ($o.type -ne 'user') { continue }
        $results = @(@($content) | Where-Object { $_ -isnot [string] -and $_.type -eq 'tool_result' })
        foreach ($r in $results | Where-Object { $_.is_error }) {
            $text = Get-Text $r.content
            $call = $calls[$r.tool_use_id]
            $cmd = if ($call) { Get-Short $call.What 120 } else { '' }
            if ($text -match 'hook error:\s*(?:harness/)?([\w-]+)\s*:\s*(.+)') {
                $key = "$($Matches[1]) : $(Get-Short $Matches[2] 160)"
                if (-not $denials[$key]) { $denials[$key] = @{ Count = 0; Commands = @{}; Sessions = [System.Collections.Generic.HashSet[string]]::new() } }
                $denials[$key].Count++; [void] $denials[$key].Sessions.Add($o.sessionId)
                # Une même raison couvre des gestes différents : chaque commande refusée garde son compte.
                if ($cmd) { $denials[$key].Commands[$cmd] = 1 + [int] $denials[$key].Commands[$cmd] }
            }
            elseif ($call) {
                # Même commande exacte, ou même outil et même erreur quand l'appel n'a pas de commande.
                $key = if ($call.What) { "$($call.Tool) : $($call.What.Trim())" } else { "$($call.Tool) : $(Get-Short $text 60)" }
                if (-not $failures[$key]) { $failures[$key] = @{ Count = 0; Label = $(if ($cmd) { "$($call.Tool) : $cmd" } else { $call.Tool }); Error = Get-Short $text 160 } }
                $failures[$key].Count++
            }
        }
        if (-not $results) {
            $text = (Get-Text $content).Trim()
            if ($text -and -not $text.StartsWith('<') -and $text -match "(?i)$correction") {
                $corrections.Add([pscustomobject]@{ Date = ([datetime] $o.timestamp).ToString('yyyy-MM-dd'); Text = Get-Short $text 200 })
            }
        }
    }
}

$out = [System.Collections.Generic.List[string]]::new()
$out.Add("# Matière de la rétro — $(Split-Path $root -Leaf), $Days derniers jours")
$out.Add('')
$out.Add("Transcripts : ``$Path`` — $($files.Count) fichier(s), $($sessions.Count) session(s).")
if (-not $files) { $out.Add('Aucun transcript sur la période.') }

$out.Add(''); $out.Add('## Refus de hooks')
if ($denials.Count) {
    foreach ($e in $denials.GetEnumerator() | Sort-Object { $_.Value.Count } -Descending) {
        $out.Add("- **$($e.Value.Count)×** ($($e.Value.Sessions.Count) session(s)) $($e.Key)")
        foreach ($c in $e.Value.Commands.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8) { $out.Add("  - $($c.Value)× ``$($c.Key)``") }
    }
} else { $out.Add('Aucun.') }

$out.Add(''); $out.Add('## Échecs répétés (2 fois ou plus)')
$repeated = @($failures.GetEnumerator() | Where-Object { $_.Value.Count -ge 2 } | Sort-Object { $_.Value.Count } -Descending)
if ($repeated) { foreach ($e in $repeated) { $out.Add("- **$($e.Value.Count)×** ``$($e.Value.Label)`` — $($e.Value.Error)") } } else { $out.Add('Aucun.') }

$out.Add(''); $out.Add("## Corrections de l'utilisateur (à relire : repérées par leurs premiers mots)")
if ($corrections.Count) { foreach ($c in $corrections | Select-Object -Last 30) { $out.Add("- $($c.Date) : « $($c.Text) »") } } else { $out.Add('Aucune.') }

if (-not $NoPrs) {
    $out.Add(''); $out.Add("## Constats d'auditor ($Prs dernières PR fusionnées)")
    $list = gh pr list --state merged --limit $Prs --json number,title,comments 2>$null
    if ($LASTEXITCODE -ne 0) { $out.Add('Lecture impossible (gh).') }
    else {
        $any = $false
        foreach ($pr in $list | ConvertFrom-Json) {
            $titles = foreach ($c in $pr.comments | Where-Object { $_.body -match 'auditor:\s*sha=' }) {
                [regex]::Matches($c.body, '(?m)^\*\*([BIM]\d+)\.\s*(.+?)\*\*(?=\s*(?:—|$))') | ForEach-Object { "$($_.Groups[1].Value) $($_.Groups[2].Value)" }
            }
            if ($titles) { $any = $true; $out.Add("- #$($pr.number) $($pr.title)"); foreach ($t in $titles | Select-Object -Unique) { $out.Add("  - $t") } }
        }
        if (-not $any) { $out.Add('Aucun constat.') }
    }
}
$out -join "`n"
