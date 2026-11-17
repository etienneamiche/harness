# infra-guard (module infra) : aucune action sur l'infra sans l'accord de l'utilisateur.
# Une action est refusée avec un code ; elle passe une seule fois, relancée à l'identique,
# après que l'utilisateur a écrit `ok infra <code>` dans le chat (règle infra-approval).
#
# Refus par défaut : un appel à kubectl, helm, tofu, terraform, argocd ou ansible* demande un code,
# sauf une lecture reconnue (kubectl get, tofu plan, ansible-playbook --check…). La commande est
# découpée selon son shell (Bash, PowerShell, cmd) : guillemets, échappements, continuations, et
# chaque substitution ($(…), (…), {…}, `…`) ou heredoc lue comme un segment à part. Le nom d'un
# programme d'infra qui apparaît ailleurs que dans une lecture reconnue ou dans le texte d'un
# programme de texte (git, rg, echo…) demande aussi un code : une forme mal lue tombe du côté sûr.
# Garde au mieux de ses moyens : l'agent tourne sous le même compte que l'utilisateur.
@{
    Name     = 'infra-guard'
    Event    = 'PreToolUse'
    Tools    = 'Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit|Agent|Task'
    Profiles = 'minimal', 'standard', 'strict'
    Kind     = 'guard'
    Run      = {
        param($ctx)
        $code = '\bok\s+infra\s+\d{4}\b'
        $stateMark = 'claude-harness(?![\w-])|claude~\d|\.infra\.json'
        $hookMark = 'HarnessHooks|UserPromptSubmit|infra-approval|dispatch\.ps1'
        $stateDeny = @{ Decision = 'deny'; Reason = "l'état des accords d'infra et les messages de l'utilisateur ne se touchent pas : seul l'utilisateur donne un accord, en écrivant ok infra <code> dans le chat." }

        if ($ctx.ToolName -in 'Agent', 'Task') {
            if ((Get-Value $ctx.ToolInput 'prompt' '') -match $code) { return $stateDeny }
            return
        }
        if ($ctx.ToolName -notin 'Bash', 'PowerShell') {
            $path = Get-Value $ctx.ToolInput 'file_path' (Get-Value $ctx.ToolInput 'notebook_path' '')
            $written = @((Get-Value $ctx.ToolInput 'content' ''), (Get-Value $ctx.ToolInput 'new_string' ''), (Get-Value $ctx.ToolInput 'new_source' '')) +
                @(@(Get-Value $ctx.ToolInput 'edits' @()) | ForEach-Object { Get-Value $_ 'new_string' '' }) -join "`n"
            if ($path -match $stateMark -or $written -match "$stateMark|$code") { return $stateDeny }
            # Un script qui appelle les hooks rejouerait un message de l'utilisateur.
            if ($path -match '\.(ps1|psm1|sh|bash|zsh|cmd|bat|py|js|mjs)$' -and $written -match $hookMark) { return $stateDeny }
            return
        }

        $raw = (Get-Value $ctx.ToolInput 'command' '').Trim()
        # Ce qui donnerait un accord sans l'utilisateur : citer un code, nommer l'état des accords,
        # reprendre une session (claude --resume rejouerait un message dans celle-ci).
        if ($raw -match $code -or $raw -match $stateMark -or
            $raw -cmatch '(?<![.\w-])claude(-code)?(\.exe|\.cmd)?\b[^;&|\n]*\s(--resume|--continue|-r|-c)(\s|=|$)') { return $stateDeny }

        $P = [string][char]1   # tient la place d'une substitution dans un mot
        $infraName = '(?<![\w.-])(kubectl|helm|tofu|terraform|argocd|ansible(-[a-z]+)?)(\.exe|\.cmd)?(?![\w./\\-])'
        $quietEvents = 'PreToolUse|PostToolUse|Stop|SubagentStop|SessionStart|SessionEnd|Notification|PreCompact'
        $prefixes = 'sudo', 'doas', 'nohup', 'command', 'time', 'nice', 'exec', 'env', 'xargs', 'k3s', 'microk8s', 'wsl', 'timeout', 'stdbuf',
            'if', 'then', 'else', 'elif', 'do', 'while', 'until', '!', '{', '}'
        $prefixValues = '-u', '-g', '-d', '--distribution', '--user', '--cd', '-n', '-s', '-k', '-I'
        $textPrograms = 'git', 'gh', 'rg', 'grep', 'egrep', 'fgrep', 'findstr', 'select-string', 'sls', 'echo', 'printf', 'write-output', 'write-host',
            'cat', 'get-content', 'gc', 'type', 'tree', 'ls', 'dir', 'gci', 'get-childitem', 'cd', 'set-location', 'sl', 'pushd', 'popd', 'head', 'tail',
            'less', 'more', 'wc', 'code', 'test-path', 'resolve-path', 'get-item', 'gi', 'join-path', 'split-path', 'sort', 'uniq', 'cut', 'tr', 'jq', 'yq',
            'mkdir', 'new-item', 'ni', 'copy-item', 'cp', 'move-item', 'mv', 'pip', 'pip3', 'apt', 'apt-get', 'winget', 'choco', 'select-object', 'select',
            'sort-object', 'where-object', 'where', '?', 'foreach-object', 'foreach', '%', 'measure-object', 'measure', 'group-object', 'format-table', 'ft',
            'format-list', 'fl', 'out-string', 'out-host', 'convertfrom-json', 'convertto-json', 'find', 'yamllint', 'du', 'stat', 'file', 'shellcheck',
            'basename', 'dirname', 'realpath', 'touch', 'tflint', 'kubeconform'
        # Lectures reconnues : verbe, et sous-verbes permis quand la valeur n'est pas vide.
        $kubectlReads = @{ get = ''; describe = ''; logs = ''; diff = ''; top = ''; explain = ''; 'api-resources' = ''; 'api-versions' = ''; version = ''
            'cluster-info' = ''; events = ''; wait = ''; 'port-forward' = ''; proxy = ''; kustomize = ''; completion = ''; options = ''; help = ''
            config = 'view|get-contexts|current-context|get-clusters|get-users'; auth = 'can-i|whoami'; plugin = 'list'; rollout = 'status|history'
        }
        $helmReads = @{ template = ''; lint = ''; list = ''; ls = ''; status = ''; history = ''; hist = ''; show = ''; inspect = ''; search = ''; repo = ''
            dependency = ''; dep = ''; version = ''; env = ''; help = ''; completion = ''; pull = ''; fetch = ''; package = ''; verify = ''; get = ''; diff = ''; plugin = ''
        }
        $argocdReads = @{ version = ''; context = ''; help = ''; completion = ''; app = 'list|get|diff|history|manifests|resources|logs|wait'; appset = 'list|get'
            proj = 'list|get'; cluster = 'list|get'; repo = 'list|get'; repocreds = 'list'; account = 'get-user-info|list|can-i|get'; cert = 'list'; gpg = 'list|get'
        }
        $tofuReads = @{ plan = ''; show = ''; validate = ''; fmt = ''; init = ''; providers = ''; version = ''; graph = ''; output = ''; get = ''; metadata = ''
            modules = ''; state = 'list|show'; workspace = 'list|show|select'
        }
        # Options sans valeur que cobra (kubectl, helm, argocd) connaît avant le verbe ; toute autre en prend une.
        $kubectlFlags = '--insecure-skip-tls-verify', '--match-server-version', '--disable-compression', '--warnings-as-errors', '-h', '--help'
        $helmFlags = '--debug', '--kube-insecure-skip-tls-verify', '-h', '--help'
        $argocdFlags = '--grpc-web', '--insecure', '--plaintext', '--core', '--port-forward', '-h', '--help'
        $kubectlDry = 'apply', 'create', 'delete', 'replace', 'patch', 'label', 'annotate', 'set', 'expose', 'run', 'scale', 'autoscale'

        # Découpe : chaque segment a ses mots (guillemets retirés, substitution remplacée par $P),
        # le segment qui contient sa substitution (Parent) et celui qui reçoit sa sortie par `|` (Next).
        function New-Cursor($s) { @{ Id = ++$s.N; Words = [Collections.Generic.List[string]]::new(); Quoted = [Collections.Generic.List[bool]]::new(); Raws = [Collections.Generic.List[string]]::new(); Holes = [Collections.Generic.List[int[]]]::new(); Start = 0; Word = [Text.StringBuilder]::new(); InWord = $false; Q = $false; Called = $false; Wait = $null } }
        function Close-Word($s, $c) {
            if (-not $c.InWord) { return }
            $w = $c.Word.ToString(); $c.Words.Add($w); $c.Quoted.Add($c.Q); $c.Raws.Add((Get-Raw $s $c)); [void]$c.Word.Clear(); $c.InWord = $false; $c.Q = $false
            if ($s.D -ne 'bash') { return }
            if ($c.Wait) { $s.Heredocs.Add(@{ Tag = $w; Strip = $c.Wait -eq '<<-' }); $c.Wait = $null }
            elseif ($w -match '^<<-?$') { $c.Wait = $w }
            elseif ($w -match '^(<<-?)(\w+)$') { $s.Heredocs.Add(@{ Tag = $Matches[2]; Strip = $Matches[1] -eq '<<-' }) }
        }
        # Texte brut d'un mot, sans le contenu de ses substitutions (lues à part).
        function Get-Raw($s, $c) {
            $end = [Math]::Min($s.I, $s.T.Length); $raw = [Text.StringBuilder]::new(); $at = $c.Start
            foreach ($h in $c.Holes) { if ($h[0] -ge $at -and $h[1] -le $end) { [void]$raw.Append($s.T.Substring($at, $h[0] - $at)); $at = $h[1] } }
            [void]$raw.Append($s.T.Substring($at, [Math]::Max(0, $end - $at))); $c.Holes.Clear()
            $raw.ToString()
        }
        function Read-Sub($s, $c, [string] $Close, $Id) {
            $from = $s.I; Read-List $s $Close $Id; $c.Holes.Add([int[]]@($from, $s.I)); [void]$c.Word.Append($P)
        }
        function Close-Segment($s, $c, $Parent, [bool] $Pipe) {
            Close-Word $s $c
            if ($c.Words.Count) {
                $seg = @{ Id = $c.Id; Words = [string[]]$c.Words; Quoted = [bool[]]$c.Quoted; Raws = [string[]]$c.Raws; Parent = $Parent; Called = $c.Called; Dialect = $s.D; Pipe = $Pipe }
                $c.Words.Clear(); $c.Quoted.Clear(); $c.Raws.Clear(); $c.Id = ++$s.N; $seg.Next = $c.Id
                $s.Out.Add($seg)
            }
            $c.Called = $false
        }
        function Read-Quoted($s, $c, [string] $q, $Id) {
            $T = $s.T; $D = $s.D
            while ($s.I -lt $T.Length) {
                $ch = [string]$T[$s.I]; $nx = if ($s.I + 1 -lt $T.Length) { [string]$T[$s.I + 1] } else { '' }
                if ($q -eq "'") {
                    if ($ch -eq "'") { if ($D -eq 'pwsh' -and $nx -eq "'") { [void]$c.Word.Append("'"); $s.I += 2; continue }; $s.I++; return }
                    [void]$c.Word.Append($ch); $s.I++; continue
                }
                if ($D -eq 'bash' -and $ch -eq '\' -and $nx -match '^["\\$`]$') { [void]$c.Word.Append($nx); $s.I += 2; continue }
                if ($D -eq 'pwsh' -and $ch -eq '`' -and $nx) { [void]$c.Word.Append($nx); $s.I += 2; continue }
                if ($D -eq 'pwsh' -and $ch -eq '"' -and $nx -eq '"') { [void]$c.Word.Append('"'); $s.I += 2; continue }
                if ($ch -eq '"') { $s.I++; return }
                if ($D -ne 'cmd' -and $ch -eq '$' -and $nx -eq '(') { $s.I += 2; Read-Sub $s $c ')' $Id; continue }
                if ($D -ne 'cmd' -and $ch -eq '$' -and $nx -eq '{') { $s.I += 2; Read-Param $s $c $Id; continue }
                if ($D -eq 'bash' -and $ch -eq '`') { $s.I++; Read-Sub $s $c '`' $Id; continue }
                [void]$c.Word.Append($ch); $s.I++
            }
        }
        # ${…} : une variable, pas une commande (ni commentaire ni séparateur), sauf ses substitutions.
        function Read-Param($s, $c, $Id) {
            $T = $s.T; $depth = 1
            while ($s.I -lt $T.Length) {
                $ch = [string]$T[$s.I]; $nx = if ($s.I + 1 -lt $T.Length) { [string]$T[$s.I + 1] } else { '' }
                if ($ch -eq '}' -and --$depth -eq 0) { $s.I++; break }
                if ($ch -eq '{') { $depth++ }
                if ($ch -eq '$' -and $nx -eq '(') { $s.I += 2; Read-Sub $s $c ')' $Id; continue }
                if ($s.D -eq 'bash' -and $ch -eq '`') { $s.I++; Read-Sub $s $c '`' $Id; continue }
                if ($s.D -eq 'bash' -and $ch -eq '\' -and $nx) { $s.I += 2; continue }
                $s.I++
            }
            [void]$c.Word.Append($P)
        }
        # Here-string PowerShell (@'…'@, @"…"@) : un seul mot, jusqu'à la ligne qui le ferme.
        function Read-HereString($s, $c, [string] $q, $Id) {
            $T = $s.T; $end = $T.IndexOf("`n$q@", $s.I); if ($end -lt 0) { $end = $T.Length }
            while ($s.I -lt $end) {
                $ch = [string]$T[$s.I]; $nx = if ($s.I + 1 -lt $T.Length) { [string]$T[$s.I + 1] } else { '' }
                if ($q -eq '"' -and $ch -eq '$' -and $nx -eq '(') { $s.I += 2; Read-Sub $s $c ')' $Id; continue }
                if ($q -eq '"' -and $ch -eq '`' -and $nx) { [void]$c.Word.Append($nx); $s.I += 2; continue }
                [void]$c.Word.Append($ch); $s.I++
            }
            $s.I = [Math]::Min([Math]::Max($s.I, $end + 3), $T.Length)
        }
        function Read-List($s, [string] $Close, $Parent) {
            $T = $s.T; $D = $s.D; $c = New-Cursor $s
            $escape = @{ bash = '\'; pwsh = '`'; cmd = '^' }[$D]
            while ($s.I -lt $T.Length) {
                $ch = [string]$T[$s.I]; $nx = if ($s.I + 1 -lt $T.Length) { [string]$T[$s.I + 1] } else { '' }
                $prev = if ($s.I -gt 0) { [string]$T[$s.I - 1] } else { '' }
                if (-not $c.InWord) { $c.Start = $s.I }
                # Ligne continuée par le caractère d'échappement de ce shell : un blanc.
                if ($ch -eq $escape -and $T.Substring($s.I + 1) -match '^\r?\n') { $s.I += 1 + $Matches[0].Length; Close-Word $s $c; continue }
                if ($Close -and $ch -eq $Close) { $s.I++; Close-Segment $s $c $Parent $false; return }
                if ($D -eq 'pwsh' -and $ch -eq '@' -and $nx -in "'", '"' -and $T.Substring($s.I + 2) -match '^[ \t]*\r?\n') {
                    if (-not $c.InWord) { $c.Q = $true }
                    $c.InWord = $true; $s.I += 2; Read-HereString $s $c $nx $c.Id; continue
                }
                if ($D -eq 'bash' -and $ch -eq '$' -and $nx -eq "'") {
                    # $'…' : chaîne de Bash où \' échappe l'apostrophe.
                    if (-not $c.InWord) { $c.Q = $true }
                    $c.InWord = $true; $s.I += 2
                    while ($s.I -lt $T.Length -and [string]$T[$s.I] -ne "'") { if ([string]$T[$s.I] -eq '\') { $s.I++ }; if ($s.I -lt $T.Length) { [void]$c.Word.Append($T[$s.I]) }; $s.I++ }
                    $s.I++; continue
                }
                if ($ch -eq '"' -or ($ch -eq "'" -and $D -ne 'cmd')) {
                    if (-not $c.InWord) { $c.Q = $true }
                    $c.InWord = $true; $s.I++; Read-Quoted $s $c $ch $c.Id; continue
                }
                if ($ch -eq '#' -and -not $c.InWord -and $D -ne 'cmd') { while ($s.I -lt $T.Length -and [string]$T[$s.I] -ne "`n") { $s.I++ }; continue }
                if ($D -eq 'pwsh' -and $ch -eq '<' -and $nx -eq '#' -and -not $c.InWord) { $end = $T.IndexOf('#>', $s.I + 2); $s.I = if ($end -lt 0) { $T.Length } else { $end + 2 }; continue }
                if ($ch -eq $escape -and $nx) { [void]$c.Word.Append($nx); $c.InWord = $true; $s.I += 2; continue }
                # Substitutions : leur contenu est un segment à part, rattaché au segment courant.
                $open = $null
                if ($D -ne 'cmd' -and $ch -eq '$' -and $nx -eq '{') { $s.I += 2; Read-Param $s $c $c.Id; $c.InWord = $true; continue }
                if ($D -ne 'cmd' -and $ch -eq '$' -and $nx -eq '(') { $open = $nx; $s.I += 2 }
                elseif ($D -eq 'pwsh' -and $ch -eq '@' -and $nx -in '(', '{') { $open = $nx; $s.I += 2 }
                elseif ($ch -eq '(' -or ($D -eq 'pwsh' -and $ch -eq '{')) { $open = $ch; $s.I++ }
                elseif ($D -eq 'bash' -and $ch -eq '`') { $open = '`'; $s.I++ }
                if ($open) { Read-Sub $s $c (@{ '(' = ')'; '{' = '}'; '`' = '`' }[$open]) $c.Id; $c.InWord = $true; continue }
                if ($ch -eq "`n") { Close-Word $s $c }
                if ($ch -eq "`n" -and $s.Heredocs.Count) {
                    # Corps des heredocs : un mot du segment qui les a ouverts.
                    $pos = $s.I + 1
                    foreach ($h in @($s.Heredocs)) {
                        $body = [Text.StringBuilder]::new()
                        while ($pos -lt $T.Length) {
                            $end = $T.IndexOf("`n", $pos); if ($end -lt 0) { $end = $T.Length }
                            $line = $T.Substring($pos, $end - $pos).TrimEnd("`r")
                            if ($(if ($h.Strip) { $line.TrimStart("`t") } else { $line }) -eq $h.Tag) { $pos = $end; break }
                            [void]$body.Append($line + "`n"); $pos = $end + 1
                        }
                        Close-Word $s $c; $c.Words.Add($body.ToString()); $c.Quoted.Add($true); $c.Raws.Add($body.ToString())
                    }
                    $s.Heredocs.Clear(); Close-Segment $s $c $Parent $false; $s.I = [Math]::Min($pos, $T.Length); continue
                }
                $amp = $ch -eq '&' -and $prev -notin '>', '<' -and $nx -ne '>'
                if ($ch -in ';', '|', "`n", ')', '}' -or $amp) {
                    if ($ch -eq '}' -and $D -eq 'bash' -and $c.InWord) { [void]$c.Word.Append($ch); $s.I++; continue }
                    $pipe = $ch -eq '|' -and $nx -ne '|'
                    Close-Segment $s $c $Parent $pipe
                    if ($nx -eq $ch -and $ch -in '&', '|', ';') { $s.I += 2 } else { $s.I++ }
                    # En PowerShell, un `&` seul est l'opérateur d'appel du segment qui suit.
                    if ($amp -and $D -eq 'pwsh' -and $nx -ne '&') { $c.Called = $true }
                    continue
                }
                if ([char]::IsWhiteSpace($ch)) { Close-Word $s $c; $s.I++; continue }
                [void]$c.Word.Append($ch); $c.InWord = $true; $s.I++
            }
            Close-Segment $s $c $Parent $false
        }
        function Split-Command([string] $Text, [string] $Dialect) {
            $s = @{ T = $Text; I = 0; D = $Dialect; N = 0; Out = [Collections.Generic.List[object]]::new(); Heredocs = [Collections.Generic.List[object]]::new() }
            Read-List $s '' $null
            , $s.Out
        }

        function Get-Program([string] $Word) { (([IO.Path]::GetFileName($Word) -replace '\.(exe|cmd|bat)$', '') -replace '^microk8s\.', '').ToLowerInvariant() }
        function Get-Count([string[]] $Words, [string] $Pattern) { [regex]::Matches(($Words -join "`n"), $Pattern, 'IgnoreCase').Count }
        function Get-BeforeDash([string[]] $A) { if (-not $A) { return }; $i = [array]::IndexOf($A, '--'); if ($i -ge 0) { @($A | Select-Object -First $i) } else { $A } }
        function Test-Dynamic([string] $Word) { ($Word -replace '^\$(env:)?CLAUDE_PROJECT_DIR(?=[\\/])', '') -match "^[\`$%]|$P" }

        # Lecture reconnue d'un programme cobra : le verbe (et son sous-verbe) est dans la table.
        function Test-CobraRead([string[]] $A, [string[]] $Flags, [hashtable] $Reads, [string[]] $DryVerbs, [string] $DryRun, [bool] $Xargs) {
            $A = Get-BeforeDash $A
            if (@($A | Where-Object { $_ -in '-h', '--help' }).Count) { return $true }
            $pos = [Collections.Generic.List[string]]::new(); $j = 0
            while ($j -lt $A.Count) {
                $x = $A[$j]
                if ($x.Length -gt 1 -and $x.StartsWith('-')) {
                    $j += $(if ($x.Contains('=') -or $x -in $Flags -or ($x.Length -gt 2 -and -not $x.StartsWith('--'))) { 1 } else { 2 })
                    continue
                }
                $pos.Add($x); $j++
            }
            # Sans verbe : une lecture (aide, version) seulement si aucun mot n'a été pris pour la valeur d'une option.
            if (-not $pos.Count) { return -not $Xargs -and -not @($A | Where-Object { -not $_.StartsWith('-') }).Count }
            $verb = $pos[0].ToLowerInvariant()
            if ($Reads.ContainsKey($verb)) { return (-not $Reads[$verb] -or ($pos.Count -gt 1 -and $pos[1] -match "^($($Reads[$verb]))$")) }
            $DryRun -and $verb -in $DryVerbs -and @($A | Where-Object { $_ -match $DryRun }).Count -gt 0
        }
        # Le cluster est nommé en clair : ni variable, ni substitution.
        function Test-Named([string[]] $A, [string] $Option) {
            $A = Get-BeforeDash $A
            for ($j = 0; $j -lt $A.Count; $j++) {
                $v = if ($A[$j] -like "$Option=*") { $A[$j].Substring($Option.Length + 1) } elseif ($A[$j] -eq $Option -and $j + 1 -lt $A.Count) { $A[$j + 1] } else { continue }
                if ($v.Trim() -and -not (Test-Dynamic $v)) { return $true }
            }
            $false
        }
        function Test-HookReplay([string] $Program, [string] $Word, [string[]] $A) {
            $rest = if ($Program -in 'pwsh', 'powershell') { @($A | Where-Object { $_ -notmatch '^-(NoProfile|NonInteractive|NoLogo|File)$' }) } else { @($Word) + $A }
            $rest.Count -eq 2 -and $rest[0] -match '(^|[\\/])dispatch\.ps1$' -and -not (Test-Dynamic $rest[0]) -and $rest[1] -match "^($quietEvents)$"
        }

        # Un segment : 'text', 'read', 'action', 'stdin' (shell qui lit son entrée) ou 'other'.
        function Read-Segment($s, $r, [int] $Depth) {
            # Les noms se cherchent dans les mots lus et dans leur texte brut (C:	ools\kubectl.exe sous Bash).
            $w = [string[]]$s.Words.Clone(); $names = Get-Count ($w + $s.Raws) $infraName; $marks = Get-Count $w $hookMark
            $flag = { if ($names) { $r.Action = $true }; if ($marks) { $r.Hook = $true } }
            $pw = $s.Dialect -eq 'pwsh'
            $k = 0; $xargs = $false
            while ($k -lt $w.Count) {
                if ($w[$k] -match '^[A-Za-z_]\w*=' -and -not $s.Quoted[$k]) { $k++; continue }
                # Affectation PowerShell, avec ou sans espaces ($x = cmd, $x=cmd) : la commande est à droite.
                if ($pw -and $w[$k] -match '^\$[\w:.]+([-+*/]?=)(.*)$') { if ($Matches[2]) { $w[$k] = $Matches[2] } else { $k++ }; continue }
                if ($pw -and $w[$k] -match '^\$' -and $k + 1 -lt $w.Count -and $w[$k + 1] -match '^[-+*/]?=(.*)$') { $k++; if ($Matches[1]) { $w[$k] = $Matches[1] } else { $k++ }; continue }
                $name = Get-Program $w[$k]
                if ($s.Quoted[$k] -or $name -notin $prefixes) { break }
                if ($name -eq 'xargs') { $xargs = $true }
                $k++
                while ($k -lt $w.Count -and $w[$k].StartsWith('-')) { $k += $(if ($w[$k] -in $prefixValues) { 2 } else { 1 }) }
                if ($name -eq 'timeout' -and $k -lt $w.Count) { $k++ }
            }
            if ($k -ge $w.Count) { & $flag; return 'other' }
            $word = $w[$k]
            # En PowerShell, un segment qui commence par une valeur ($x, (…), 'texte', 12) est une expression.
            if ($pw -and -not ($s.Called -and $k -eq 0) -and ($s.Quoted[$k] -or $word -match "^[\`$\d@\[]|^$P")) {
                # Sauf un appel .NET qui lance un processus ou un script : [Diagnostics.Process]::Start(…), InvokeScript(…).
                if (($w -join ' ') -match '::|\.(invoke\w*|addscript|start|create\w*)\b') { & $flag; return 'other' }
                return 'text'
            }
            if (Test-Dynamic $word) { $r.Dynamic = $true; & $flag; return 'other' }
            $program = Get-Program $word
            $arguments = [string[]]@($w | Select-Object -Skip ($k + 1))
            if ($program -in $textPrograms) {
                # Sauf quand il lance une commande (git submodule foreach, find -exec) ou écrit un script.
                $runs = ($program -eq 'git' -and @($arguments | Where-Object { $_ -match '^(foreach|run|--exec|-x)$|^(alias|core)\.' }).Count) -or
                    ($program -eq 'find' -and @($arguments | Where-Object { $_ -match '^-(exec|execdir|ok|okdir)$' }).Count) -or
                    ($program -in 'new-item', 'ni', 'copy-item', 'cp', 'move-item', 'mv' -and @($arguments | Where-Object { $_ -match '\.(ps1|psm1|sh|bash|zsh|cmd|bat|py)$' }).Count)
                if ($runs) { & $flag; return 'other' }
                return 'text'
            }

            # Un shell : son script est relu par la même lecture, dans son propre dialecte.
            if ($program -match '^(bash|sh|zsh|dash|pwsh|powershell|cmd|iex|invoke-expression|ssh|watch)$') {
                $script = $null; $from = -1; $file = $null; $stdin = $false
                $dialect = @{ pwsh = 'pwsh'; powershell = 'pwsh'; iex = 'pwsh'; 'invoke-expression' = 'pwsh'; cmd = 'cmd' }[$program] ?? 'bash'
                $positional = @($arguments | Where-Object { -not $_.StartsWith('-') })
                switch -Regex ($program) {
                    '^(bash|sh|zsh|dash)$' {
                        $o = [array]::FindIndex($arguments, [Predicate[string]] { param($x) $x -match '^-[a-z]*c[a-z]*$' })
                        if ($o -ge 0 -and $o + 1 -lt $arguments.Count) { $from = $o + 1; $script = $arguments[$from]; $arguments = @($arguments | Select-Object -First $from) + @($arguments | Select-Object -Skip ($from + 1)) }
                        elseif ($positional.Count -and $arguments -notcontains '-s') { $file = $positional[0] } else { $stdin = $true }
                    }
                    '^(pwsh|powershell)$' {
                        if (@($arguments | Where-Object { $_ -match '^-(e|ec|en|enc|enco\w*|encodedcommand)$' }).Count) { $r.Action = $true; return 'other' }
                        $o = [array]::FindIndex($arguments, [Predicate[string]] { param($x) $x -match '^-(c|co|com|comm|comma|comman|command)$' })
                        $f = [array]::FindIndex($arguments, [Predicate[string]] { param($x) $x -match '^-(f|fi|fil|file)$' })
                        if ($o -ge 0) { $script = ($arguments | Select-Object -Skip ($o + 1)) -join ' '; $arguments = @($arguments | Select-Object -First $o) }
                        elseif ($f -ge 0 -and $f + 1 -lt $arguments.Count) { $file = $arguments[$f + 1] }
                        elseif ($positional.Count) { $file = $positional[0] } else { $stdin = $true }
                        if ($script -eq '-' -or $file -eq '-') { $script = $null; $file = $null; $stdin = $true }
                    }
                    '^cmd$' {
                        $o = [array]::FindIndex($arguments, [Predicate[string]] { param($x) $x -match '^/[ck]$' })
                        if ($o -ge 0) { $script = ($arguments | Select-Object -Skip ($o + 1)) -join ' '; $arguments = @($arguments | Select-Object -First $o) } else { $stdin = $true }
                    }
                    '^(iex|invoke-expression)$' {
                        $a = @($arguments | Where-Object { $_ -notmatch '^-(c|co|com|comm|comma|comman|command)$' })
                        if ($a.Count) { $script = $a -join ' '; $arguments = @() } else { $stdin = $true }
                    }
                    '^watch$' {
                        $j = 0
                        while ($j -lt $arguments.Count -and $arguments[$j].StartsWith('-')) { $j += $(if ($arguments[$j] -in '-n', '--interval') { 2 } else { 1 }) }
                        if ($j -lt $arguments.Count) { $script = ($arguments | Select-Object -Skip $j) -join ' '; $arguments = @($arguments | Select-Object -First $j) }
                    }
                    '^ssh$' {
                        $j = 0
                        while ($j -lt $arguments.Count -and $arguments[$j].StartsWith('-')) { $j += $(if ($arguments[$j] -cmatch '^-[pilFoJLRDWbcemOQSw]$') { 2 } else { 1 }) }
                        if ($j + 1 -lt $arguments.Count) { $script = ($arguments | Select-Object -Skip ($j + 1)) -join ' '; $arguments = @($arguments | Select-Object -First ($j + 1)) }
                    }
                }
                $outer = @($w | Select-Object -First ($k + 1)) + $arguments
                if (Get-Count $outer $infraName) { $r.Action = $true }
                if ((Get-Count $outer $hookMark) -and -not ($null -eq $s.Parent -and $null -ne $file -and (Get-Count $outer $hookMark) -eq 1 -and (Test-HookReplay $program $word $arguments))) { $r.Hook = $true }
                if ($null -ne $file -and (Test-Dynamic $file)) { $r.Dynamic = $true }
                if ($null -ne $script) {
                    if (Test-Dynamic $script.Trim()) { $r.Dynamic = $true }
                    if ($Depth -ge 4) { $r.Action = $true; return 'other' }
                    $sub = Read-Command $script $dialect ($Depth + 1)
                    # Sur un nœud (ssh), kubectl vise le cluster de ce nœud : le contexte n'est pas exigé.
                    foreach ($key in @($r.Keys)) { if ($program -eq 'ssh' -and $key -eq 'Context') { continue }; $r[$key] = $r[$key] -or $sub[$key] }
                }
                if ($stdin) { return 'stdin' }
                return 'other'
            }

            if ($marks -and -not ($marks -eq 1 -and $null -eq $s.Parent -and (Test-HookReplay $program $word $arguments))) { $r.Hook = $true }
            $read = $null
            switch ($program) {
                'kubectl' {
                    $read = Test-CobraRead $arguments $kubectlFlags $kubectlReads $kubectlDry '^--dry-run=(client|server)$' $xargs
                    if (-not $read -and -not (Test-Named $arguments '--context')) { $r.Context = $true }
                }
                'helm' {
                    $read = Test-CobraRead $arguments $helmFlags $helmReads @('install', 'upgrade') '^--dry-run(=(client|server|true))?$' $xargs
                    if (-not $read -and -not (Test-Named $arguments '--kube-context')) { $r.Context = $true }
                }
                'argocd' { $read = Test-CobraRead $arguments $argocdFlags $argocdReads @() '' $xargs }
                { $_ -in 'tofu', 'terraform' } {
                    $pos = @($arguments | Where-Object { -not $_.StartsWith('-') })
                    if (@($arguments | Where-Object { $_ -in '-help', '-h', '--help' }).Count -or (-not $pos.Count -and -not $xargs)) { $read = $true; break }
                    $verb = "$($pos[0])".ToLowerInvariant()
                    if ($tofuReads.ContainsKey($verb)) {
                        $read = -not $tofuReads[$verb] -or ($pos.Count -gt 1 -and $pos[1] -match "^($($tofuReads[$verb]))$")
                        if ($verb -eq 'init' -and @($arguments | Where-Object { $_ -match '^-(migrate-state|force-copy)' }).Count) { $read = $false }
                        break
                    }
                    $read = $false
                    if ($verb -eq 'destroy') { $r.Destroy = $true; break }
                    if ($verb -eq 'apply' -and -not @($pos | Select-Object -Skip 1 | Where-Object { $_ -match '\.tfplan$' -and $_ -notmatch '=' -and -not (Test-Dynamic $_) }).Count) { $r.Plan = $true }
                }
                'ansible-playbook' {
                    $a = @(Get-BeforeDash $arguments)
                    $read = [bool]@($a | Where-Object { $_ -in '--check', '--syntax-check', '--list-tasks', '--list-hosts', '--list-tags', '-h', '--help', '--version' -or $_ -ceq '-C' }).Count
                }
                'ansible' { $a = @(Get-BeforeDash $arguments); $read = -not $a.Count -or [bool]@($a | Where-Object { $_ -in '--version', '-h', '--help', '--list-hosts' }).Count }
                { $_ -in 'ansible-lint', 'ansible-galaxy', 'ansible-inventory', 'ansible-doc', 'ansible-config', 'ansible-vault', 'ansible-test', 'ansible-creator' } { $read = $true }
                { $_ -match '^ansible-' } { if ($null -eq $read) { $read = $false } }
            }
            if ($null -eq $read) { & $flag; return 'other' }
            if ($read) { return 'read' }
            $r.Action = $true
            'action'
        }

        function Read-Command([string] $Text, [string] $Dialect, [int] $Depth) {
            $r = @{ Action = $false; Context = $false; Plan = $false; Destroy = $false; Hook = $false; Dynamic = $false }
            $segments = Split-Command $Text $Dialect
            $kind = @{}; $byId = @{}
            foreach ($s in $segments) { $byId[$s.Id] = $s; $kind[$s.Id] = Read-Segment $s $r $Depth }
            $stdin = $kind.Values -contains 'stdin'
            # Le texte d'un programme de texte ne compte pas, sauf s'il part vers un shell, un script
            # ou un autre programme : il pourrait alors devenir une commande.
            $explained = {
                param($s)
                if ($kind[$s.Id] -eq 'read') { return $true }
                if ($kind[$s.Id] -ne 'text' -or $stdin) { return $false }
                for ($j = 0; $j -lt $s.Words.Count; $j++) {
                    if ($s.Quoted[$j] -or $s.Words[$j] -notmatch '^(\d|&|\*)?>>?(.*)$') { continue }
                    $target = if ($Matches[2]) { $Matches[2] } elseif ($j + 1 -lt $s.Words.Count) { $s.Words[$j + 1] } else { '' }
                    if ($target -match '\.(ps1|psm1|sh|bash|zsh|cmd|bat|py)$') { return $false }
                }
                if ($s.Pipe -and $kind[$s.Next] -notin 'text', 'read') { return $false }
                if ($null -eq $s.Parent -or -not $byId.ContainsKey($s.Parent)) { return $true }
                & $explained $byId[$s.Parent]
            }
            foreach ($s in $segments) {
                if ($kind[$s.Id] -notin 'text', 'read' -or (& $explained $s)) { continue }
                if (Get-Count ($s.Words + $s.Raws) $infraName) { $r.Action = $true }
                if (Get-Count $s.Words $hookMark) { $r.Hook = $true }
            }
            $r
        }

        $result = Read-Command $raw $(if ($ctx.ToolName -eq 'PowerShell') { 'pwsh' } else { 'bash' }) 0
        # Un programme ou un script qui vient d'une variable : la commande ne se lit pas jusqu'au bout.
        if ($result.Dynamic) { if ($raw -match $infraName) { $result.Action = $true }; if ($raw -match $hookMark) { $result.Hook = $true } }
        if ($result.Hook) { return $stateDeny }
        if ($result.Destroy) {
            return @{ Decision = 'deny'; Reason = "pas de tofu destroy direct : tofu plan -destroy -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($result.Plan) {
            return @{ Decision = 'deny'; Reason = "tofu apply se lance sur un plan enregistré : tofu plan -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($result.Context) {
            return @{ Decision = 'deny'; Reason = "nommer le cluster visé, en clair : kubectl --context <cluster>, helm --kube-context <cluster>. Le contexte courant peut être le mauvais cluster." }
        }
        if (-not $result.Action) { return }

        # Accord donné pour cette commande-là : il sert une fois. L'empreinte est salée par un secret
        # de la session, pour qu'un accord ne se calcule pas d'avance.
        $state = Get-HarnessStatePath $ctx.SessionId 'infra'
        $data = if (Test-Path $state) { Get-Content $state -Raw | ConvertFrom-Json -AsHashtable } else { $null }
        if (-not $data) { $data = @{} }
        if (-not $data['salt']) { $data['salt'] = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(16)) }
        $pending = $data['pending'] ?? @{}
        $approved = @($data['approved'] ?? @())
        $key = Get-StringHash "$($data['salt'])`n$raw"
        if ($approved -contains $key) {
            $data['approved'] = @($approved | Where-Object { $_ -ne $key })
            ConvertTo-Json -InputObject $data -Compress | Set-Content $state
            return
        }

        $grant = @($pending.Keys | Where-Object { $pending[$_] -eq $key }) | Select-Object -First 1
        if (-not $grant) {
            do { $grant = '{0:D4}' -f [Security.Cryptography.RandomNumberGenerator]::GetInt32(10000) } while ($pending.ContainsKey($grant))
            $pending[$grant] = $key
            $data['pending'] = $pending
            $data['approved'] = $approved
            ConvertTo-Json -InputObject $data -Compress | Set-Content $state
        }
        @{ Decision = 'deny'; Reason = @"
action sur l'infra, qui demande l'accord de l'utilisateur. Avant de la relancer à l'identique :
1. montre-lui la commande exacte et ce qu'elle va changer (le plan, le diff, --check --diff) ;
2. donne en une ligne la façon de revenir en arrière ;
3. demande-lui d'écrire, seul dans son message : ok infra $grant
Cet accord vaut pour cette commande, une seule fois. Ne l'écris jamais toi-même, ni dans une commande.
"@ }
    }
}
