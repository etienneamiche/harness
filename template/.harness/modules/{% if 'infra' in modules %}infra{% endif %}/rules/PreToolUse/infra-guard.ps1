# infra-guard (module infra) : aucune action sur l'infra sans l'accord de l'utilisateur.
# Une action est refusée avec un code ; elle passe une seule fois, relancée à l'identique,
# après que l'utilisateur a écrit `ok infra <code>` dans le chat (règle infra-approval).
#
# La commande est lue segment par segment (`;`, `|`, `&`, `(`, `)`, saut de ligne, hors des
# guillemets ; une ligne continuée par `\` ou `` ` `` reste un seul segment). Le programme de
# chaque segment, après `NOM=valeur` et les préfixes (wsl, sudo, timeout…), décide :
# - programme d'infra (kubectl, helm, tofu, ansible-playbook…) : son verbe est lu à sa place ;
# - shell avec un script (bash -lc "…", ssh hôte "…", cmd /c, pwsh -C, iex) : le script est relu ;
# - programme de texte (git, rg, cat, echo…) : le segment ne compte pas, c'est du texte ;
# - tout autre programme : recherche large dans tout son texte, guillemets compris.
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
        $stateMark = 'claude-harness|\.infra\.json'
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
            return
        }

        $raw = (Get-Value $ctx.ToolInput 'command' '').Trim()
        # Ce qui donnerait un accord sans l'utilisateur : citer un code, nommer l'état des accords,
        # reprendre une session (claude --resume rejouerait un message dans celle-ci).
        if ($raw -match $code -or $raw -match $stateMark -or
            $raw -cmatch '(?<![.\w-])claude(-code)?(\.exe|\.cmd)?\b[^;&|\n]*\s(--resume|--continue|-r|-c)(\s|=|$)') { return $stateDeny }

        $prefixes = 'sudo', 'doas', 'nohup', 'command', 'time', 'nice', 'exec', 'env', 'xargs', 'k3s', 'microk8s', 'wsl', 'timeout', 'stdbuf', 'watch'
        $prefixValues = '-u', '-g', '-d', '--distribution', '--user', '--cd', '-n', '-s', '-k', '-I'
        $textPrograms = 'git', 'gh', 'rg', 'grep', 'egrep', 'fgrep', 'findstr', 'select-string', 'sls', 'echo', 'printf', 'write-output',
            'write-host', 'cat', 'get-content', 'gc', 'type', 'tree', 'ls', 'dir', 'gci', 'get-childitem', 'cd', 'set-location', 'sl',
            'pushd', 'popd', 'head', 'tail', 'less', 'more', 'wc', 'code', 'test-path', 'resolve-path', 'get-item', 'gi', 'join-path',
            'split-path', 'sort', 'uniq', 'jq', 'yq', 'sed', 'mkdir', 'new-item', 'ni', 'copy-item', 'cp', 'move-item', 'mv', 'pip', 'pip3',
            'apt', 'apt-get', 'winget', 'choco'
        $kubeVerbs = 'apply', 'create', 'delete', 'replace', 'patch', 'edit', 'scale', 'rollout', 'drain', 'cordon', 'uncordon', 'label',
            'annotate', 'taint', 'set', 'autoscale', 'expose', 'run', 'exec', 'cp', 'debug', 'auth', 'certificate'
        $kubeValues = '-n', '--namespace', '--context', '--kubeconfig', '--cluster', '--user', '-s', '--server', '--as', '--as-group', '--token', '--request-timeout', '-c', '--container', '-l', '--selector', '-f', '--filename', '-o', '--output'
        $helmVerbs = 'install', 'upgrade', 'rollback', 'uninstall', 'delete', 'test'
        $helmValues = '-n', '--namespace', '--kube-context', '--kubeconfig', '--kube-apiserver', '--kube-as-user', '--kube-token', '-f', '--values', '--set', '--version'
        $tofuVerbs = 'apply', 'import', 'taint', 'untaint', 'force-unlock', 'refresh', 'test', 'state', 'workspace'
        $loose = @(
            "\b(kubectl|helm)(\.exe)?\b[^\n]*?[\s,]['`"]?($(($kubeVerbs + $helmVerbs) -join '|'))['`"]?([\s,]|$)",
            "\b(tofu|terraform)(\.exe)?\b[^\n]*?[\s,]['`"]?(apply|destroy|import|taint|untaint|force-unlock|refresh|test|state\s+(rm|mv|push|replace-provider)|workspace\s+delete)['`"]?([\s,]|$)",
            "\bansible-playbook\b(?![^\n]*\s(--check|--syntax-check|(?-i:-C))(\s|['`"]|$))",
            "\bansible(-pull|-console)?(\.exe)?(?![-\w])[^\n]*\s(-m|-a|--module-name|--args)\b",
            "\bargocd\b[^\n]*?\s(app\s+(sync|delete|set|unset|patch|rollback|create|terminate-op|actions)|appset\s+(create|delete)|proj\s+(create|delete)|cluster\s+(add|rm))\b"
        )
        # Rejouer un hook pour l'expliquer (/help-harness) reste permis, sauf l'événement des messages.
        $quietEvents = 'PreToolUse|PostToolUse|Stop|SubagentStop|SessionStart|SessionEnd|Notification|PreCompact'
        $hookCall = { param($t) ($t -match 'HarnessHooks|UserPromptSubmit|infra-approval') -or ($t -match 'dispatch\.ps1' -and $t -notmatch "dispatch\.ps1['`"]?\s+['`"]?($quietEvents)['`"]?(\s|$)") }

        # Découpe en segments, chacun avec ses mots (guillemets retirés) et son texte brut.
        function Split-Segments([string] $Text) {
            $segments = [Collections.Generic.List[object]]::new()
            $words = [Collections.Generic.List[string]]::new(); $word = [Text.StringBuilder]::new(); $plain = [Text.StringBuilder]::new()
            $inWord = $false; $quote = $null
            for ($i = 0; $i -le $Text.Length; $i++) {
                $c = if ($i -lt $Text.Length) { $Text[$i] } else { "`n" }
                # Ligne continuée : `\` ou `` ` `` suivi d'un saut de ligne vaut un blanc.
                if ($c -in '\', '`' -and $i + 1 -lt $Text.Length -and $Text.Substring($i + 1) -match '^\r?\n') {
                    $i += $Matches[0].Length; $c = ' '
                    if ($quote) { [void]$word.Append(' '); [void]$plain.Append(' '); continue }
                }
                if ($quote) { if ($c -eq $quote) { $quote = $null } else { [void]$word.Append($c) }; [void]$plain.Append($c); continue }
                if ($c -eq '#' -and -not $inWord) { while ($i + 1 -lt $Text.Length -and $Text[$i + 1] -ne "`n") { $i++ }; continue }
                if ($c -in "'", '"') { $quote = $c; $inWord = $true; [void]$plain.Append($c); continue }
                if ([char]::IsWhiteSpace($c) -or $c -in ';', '|', '&', '(', ')') {
                    if ($inWord) { $words.Add($word.ToString()); [void]$word.Clear(); $inWord = $false }
                    if ($c -in ';', '|', '&', '(', ')', "`n", "`r") {
                        if ($words.Count) { $segments.Add(@{ Words = @($words); Text = $plain.ToString() }) }
                        $words = [Collections.Generic.List[string]]::new(); [void]$plain.Clear()
                    }
                    else { [void]$plain.Append($c) }
                    continue
                }
                [void]$word.Append($c); [void]$plain.Append($c); $inWord = $true
            }
            , $segments
        }

        # Le verbe d'un programme d'infra : le premier mot qui n'est pas une option. Une option inconnue
        # sans `=` prend le mot suivant pour valeur, sauf si ce mot est un verbe d'action. Rest : les
        # arguments qui suivent le verbe, sans les options ni leurs valeurs.
        function Get-Verb([string[]] $Arguments, [string[]] $ValueOptions, [string[]] $Verbs) {
            $positional = [Collections.Generic.List[string]]::new()
            $j = 0
            while ($j -lt $Arguments.Count) {
                $a = $Arguments[$j]
                if ($a -eq '--') { break }
                if ($a.StartsWith('-')) {
                    if ($a.Contains('=')) { $j++ }
                    elseif ($a -in $ValueOptions) { $j += 2 }
                    elseif ($ValueOptions -and $j + 1 -lt $Arguments.Count -and $Arguments[$j + 1] -notin $Verbs -and -not $Arguments[$j + 1].StartsWith('-') -and -not $positional.Count) { $j += 2 }
                    else { $j++ }
                    continue
                }
                $positional.Add($a); $j++
            }
            if ($positional.Count) { @{ Verb = $positional[0].ToLowerInvariant(); Rest = @($positional | Select-Object -Skip 1) } }
        }

        function Read-Command([string] $Text, [int] $Depth) {
            $r = @{ Action = $false; Context = $false; Plan = $false; Destroy = $false; Hook = $false }
            $segments = Split-Segments $Text
            foreach ($s in $segments) {
                $w = $s.Words; $k = 0
                while ($k -lt $w.Count) {
                    if ($w[$k] -match '^[A-Za-z_]\w*=') { $k++; continue }
                    $name = ([IO.Path]::GetFileName($w[$k]) -replace '\.(exe|cmd)$', '').ToLowerInvariant()
                    if ($name -notin $prefixes) { break }
                    $k++
                    while ($k -lt $w.Count -and $w[$k].StartsWith('-')) { $k += $(if ($w[$k] -in $prefixValues) { 2 } else { 1 }) }
                    if ($name -eq 'timeout' -and $k -lt $w.Count) { $k++ }
                }
                if ($k -ge $w.Count) { continue }
                $program = ([IO.Path]::GetFileName($w[$k]) -replace '\.(exe|cmd)$', '').ToLowerInvariant()
                $arguments = @($w | Select-Object -Skip ($k + 1))
                if ($program -in $textPrograms) { continue }
                if (& $hookCall $s.Text) { $r.Hook = $true }

                # Un shell avec un script : le script est relu par la même lecture.
                $script = $null
                switch -Regex ($program) {
                    '^(bash|sh|zsh|dash)$' { $o = [array]::FindIndex([string[]]$arguments, [Predicate[string]] { param($x) $x -match '^-[a-z]*c[a-z]*$' }); if ($o -ge 0 -and $o + 1 -lt $arguments.Count) { $script = $arguments[$o + 1] } }
                    '^(pwsh|powershell)$' { $o = [array]::FindIndex([string[]]$arguments, [Predicate[string]] { param($x) $x -match '^-(c|command)$' }); if ($o -ge 0) { $script = ($arguments | Select-Object -Skip ($o + 1)) -join ' ' } }
                    '^cmd$' { $o = [array]::FindIndex([string[]]$arguments, [Predicate[string]] { param($x) $x -match '^/[ck]$' }); if ($o -ge 0) { $script = ($arguments | Select-Object -Skip ($o + 1)) -join ' ' } }
                    '^(iex|invoke-expression)$' { $script = $arguments -join ' ' }
                    '^ssh$' {
                        $j = 0
                        while ($j -lt $arguments.Count -and $arguments[$j].StartsWith('-')) { $j += $(if ($arguments[$j] -cmatch '^-[pilFoJLRDWbcemOQSw]$') { 2 } else { 1 }) }
                        if ($j + 1 -lt $arguments.Count) { $script = ($arguments | Select-Object -Skip ($j + 1)) -join ' ' }
                    }
                }
                if ($null -ne $script) {
                    if ($Depth -lt 4) {
                        $sub = Read-Command $script ($Depth + 1)
                        # Sur un nœud (ssh), kubectl vise le cluster de ce nœud : le contexte n'est pas exigé.
                        foreach ($key in @($r.Keys)) { if ($program -eq 'ssh' -and $key -eq 'Context') { continue }; $r[$key] = $r[$key] -or $sub[$key] }
                    }
                    else { $r.Action = $true }
                    continue
                }

                switch ($program) {
                    'kubectl' {
                        $v = Get-Verb $arguments $kubeValues $kubeVerbs
                        if (-not $v -or $v.Verb -notin $kubeVerbs) { break }
                        $sub = @{ rollout = 'restart|undo|pause|resume'; auth = 'reconcile'; certificate = 'approve|deny' }[$v.Verb]
                        if ($sub -and "$($v.Rest[0])" -notmatch "^($sub)$") { break }
                        $r.Action = $true
                        if (-not @($arguments | Where-Object { $_ -eq '--context' -or $_ -like '--context=?*' })) { $r.Context = $true }
                    }
                    'helm' {
                        $v = Get-Verb $arguments $helmValues $helmVerbs
                        if (-not $v -or $v.Verb -notin $helmVerbs) { break }
                        $r.Action = $true
                        if (-not @($arguments | Where-Object { $_ -eq '--kube-context' -or $_ -like '--kube-context=?*' })) { $r.Context = $true }
                    }
                    { $_ -in 'tofu', 'terraform' } {
                        $v = Get-Verb $arguments @() $tofuVerbs
                        if (-not $v) { break }
                        if ($v.Verb -eq 'destroy') { $r.Destroy = $true; break }
                        if ($v.Verb -notin $tofuVerbs) { break }
                        if ($v.Verb -eq 'state' -and "$($v.Rest[0])" -notin 'rm', 'mv', 'push', 'replace-provider') { break }
                        if ($v.Verb -eq 'workspace' -and "$($v.Rest[0])" -ne 'delete') { break }
                        $r.Action = $true
                        if ($v.Verb -eq 'apply' -and -not @($v.Rest | Where-Object { $_ -match '\.tfplan$' -and $_ -notmatch '=' })) { $r.Plan = $true }
                    }
                    'ansible-playbook' { if (-not @($arguments | Where-Object { $_ -in '--check', '--syntax-check', '--list-tasks', '--list-hosts', '--list-tags' -or $_ -ceq '-C' })) { $r.Action = $true } }
                    { $_ -in 'ansible-pull', 'ansible-console' } { $r.Action = $true }
                    'ansible' { if ($arguments.Count -and -not @($arguments | Where-Object { $_ -in '--version', '-h', '--help', '--list-hosts' })) { $r.Action = $true } }
                    'argocd' { if (Test-AnyMatch $s.Text @($loose[4])) { $r.Action = $true } }
                    { $_ -in 'ansible-lint', 'ansible-galaxy', 'ansible-inventory', 'ansible-doc', 'ansible-config', 'ansible-vault' } { }
                    default { if (Test-AnyMatch $s.Text $loose) { $r.Action = $true } }
                }
            }
            # Un texte envoyé à un shell qui lit l'entrée (`echo '…' | bash`) se lit en entier.
            $last = @($segments)[-1]
            if ($segments.Count -gt 1 -and $last -and ([IO.Path]::GetFileName($last.Words[0]) -replace '\.(exe|cmd)$', '') -match '^(bash|sh|zsh|pwsh|powershell|cmd|iex|invoke-expression)$') {
                if (& $hookCall $Text) { $r.Hook = $true }
                if (Test-AnyMatch $Text $loose) { $r.Action = $true }
            }
            $r
        }

        $result = Read-Command $raw 0
        if ($result.Hook) { return $stateDeny }
        if ($result.Destroy) {
            return @{ Decision = 'deny'; Reason = "pas de tofu destroy direct : tofu plan -destroy -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($result.Plan) {
            return @{ Decision = 'deny'; Reason = "tofu apply se lance sur un plan enregistré : tofu plan -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($result.Context) {
            return @{ Decision = 'deny'; Reason = "nommer le cluster visé : kubectl --context <cluster>, helm --kube-context <cluster>. Le contexte courant peut être le mauvais cluster." }
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
