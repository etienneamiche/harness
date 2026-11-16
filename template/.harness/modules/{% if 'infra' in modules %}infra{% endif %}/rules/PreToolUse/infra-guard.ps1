# infra-guard (module infra) : aucune action sur l'infra sans l'accord de l'utilisateur.
# Une action est refusée avec un code ; elle passe une seule fois, relancée à l'identique,
# après que l'utilisateur a écrit `ok infra <code>` dans le chat (règle infra-approval).
#
# La commande est lue segment par segment (`;`, `|`, `&`, saut de ligne, hors des guillemets).
# Le programme de chaque segment, après `NOM=valeur` et les préfixes (wsl, sudo, timeout…), décide :
# - programme d'infra (kubectl, helm, tofu, ansible-playbook…) : son verbe est lu à sa place ;
# - programme de texte (git, rg, cat, echo…) : le segment ne compte pas, c'est du texte ;
# - tout autre programme (bash -lc, ssh, cmd /c, iex…) : recherche large, guillemets compris.
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
        $hookMark = 'dispatch\.ps1|HarnessHooks|UserPromptSubmit|infra-approval'
        $stateDeny = @{ Decision = 'deny'; Reason = "l'état des accords d'infra et les messages de l'utilisateur ne se touchent pas : seul l'utilisateur donne un accord, en écrivant ok infra <code> dans le chat." }

        if ($ctx.ToolName -in 'Agent', 'Task') {
            if ((Get-Value $ctx.ToolInput 'prompt' '') -match $code) { return $stateDeny }
            return
        }
        if ($ctx.ToolName -notin 'Bash', 'PowerShell') {
            $path = Get-Value $ctx.ToolInput 'file_path' (Get-Value $ctx.ToolInput 'notebook_path' '')
            $text = @((Get-Value $ctx.ToolInput 'content' ''), (Get-Value $ctx.ToolInput 'new_string' ''), (Get-Value $ctx.ToolInput 'new_source' '')) +
                @(@(Get-Value $ctx.ToolInput 'edits' @()) | ForEach-Object { Get-Value $_ 'new_string' '' }) -join "`n"
            if ($path -match $stateMark -or $text -match "$stateMark|UserPromptSubmit|$code") { return $stateDeny }
            return
        }

        $raw = (Get-Value $ctx.ToolInput 'command' '').Trim()
        if ($raw -match $code -or $raw -match $stateMark) { return $stateDeny }

        # Découpe en segments, chacun avec ses mots (guillemets retirés) et son texte brut.
        $segments = [Collections.Generic.List[object]]::new()
        $words = [Collections.Generic.List[string]]::new(); $word = [Text.StringBuilder]::new(); $text = [Text.StringBuilder]::new()
        $inWord = $false; $quote = $null
        for ($i = 0; $i -le $raw.Length; $i++) {
            $c = if ($i -lt $raw.Length) { $raw[$i] } else { "`n" }
            if ($quote) { if ($c -eq $quote) { $quote = $null } else { [void]$word.Append($c) }; [void]$text.Append($c); continue }
            if ($c -eq '#' -and -not $inWord) { while ($i + 1 -lt $raw.Length -and $raw[$i + 1] -ne "`n") { $i++ }; continue }
            if ($c -in "'", '"') { $quote = $c; $inWord = $true; [void]$text.Append($c); continue }
            if ([char]::IsWhiteSpace($c) -or $c -in ';', '|', '&') {
                if ($inWord) { $words.Add($word.ToString()); [void]$word.Clear(); $inWord = $false }
                if ($c -in ';', '|', '&', "`n", "`r") {
                    if ($words.Count) { $segments.Add(@{ Words = @($words); Text = $text.ToString() }) }
                    $words = [Collections.Generic.List[string]]::new(); [void]$text.Clear()
                }
                else { [void]$text.Append($c) }
                continue
            }
            [void]$word.Append($c); [void]$text.Append($c); $inWord = $true
        }

        $prefixes = 'sudo', 'doas', 'nohup', 'command', 'time', 'nice', 'exec', 'env', 'xargs', 'k3s', 'wsl', 'timeout', 'stdbuf'
        $prefixValues = '-u', '-g', '-d', '--distribution', '--user', '--cd', '-n', '-s', '-k', '-I'
        $textPrograms = 'git', 'gh', 'rg', 'grep', 'egrep', 'fgrep', 'findstr', 'select-string', 'sls', 'echo', 'printf', 'write-output',
            'write-host', 'cat', 'get-content', 'gc', 'type', 'tree', 'ls', 'dir', 'gci', 'get-childitem', 'cd', 'set-location', 'sl',
            'pushd', 'popd', 'head', 'tail', 'less', 'more', 'wc', 'code', 'test-path', 'resolve-path', 'get-item', 'gi', 'join-path',
            'split-path', 'sort', 'uniq', 'jq', 'yq', 'sed'
        $shells = 'bash', 'sh', 'zsh', 'pwsh', 'powershell', 'cmd', 'iex', 'invoke-expression'
        $kubeVerbs = 'apply', 'create', 'delete', 'replace', 'patch', 'edit', 'scale', 'rollout', 'drain', 'cordon', 'uncordon', 'label',
            'annotate', 'taint', 'set', 'autoscale', 'expose', 'run', 'exec', 'cp', 'debug', 'auth', 'certificate'
        $helmVerbs = 'install', 'upgrade', 'rollback', 'uninstall', 'delete', 'test'
        $tofuVerbs = 'apply', 'import', 'taint', 'untaint', 'force-unlock', 'refresh', 'test', 'state', 'workspace'
        $loose = @(
            "\b(kubectl|helm)(\.exe)?\b[^\n]*?\s['`"]?($(($kubeVerbs + $helmVerbs) -join '|'))['`"]?(\s|$)",
            "\b(tofu|terraform)(\.exe)?\b[^\n]*?\s['`"]?(apply|destroy|import|taint|untaint|force-unlock|refresh|test|state\s+(rm|mv|push|replace-provider)|workspace\s+delete)['`"]?(\s|$)",
            "\bansible-playbook\b(?![^\n]*\s(--check|(?-i:-C))(\s|['`"]|$))",
            "\bansible(-pull|-console)?(\.exe)?(?![-\w])(?!\s+--version\b)\s+[^\s'`"]",
            "\bargocd\b[^\n]*?\s(app\s+(sync|delete|set|unset|patch|rollback|create|terminate-op|actions)|appset\s+(create|delete)|proj\s+(create|delete)|cluster\s+(add|rm))\b"
        )

        # Le verbe d'un programme d'infra : le premier mot qui n'est pas une option. Une option inconnue
        # sans `=` prend le mot suivant pour valeur, sauf si ce mot est un verbe d'action.
        function Get-Verb([string[]] $Arguments, [string[]] $ValueOptions, [string[]] $Verbs) {
            $j = 0
            while ($j -lt $Arguments.Count) {
                $a = $Arguments[$j]
                if ($a -eq '--') { return $null }
                if ($a.StartsWith('-')) {
                    if ($a.Contains('=')) { $j++ }
                    elseif ($a -in $ValueOptions) { $j += 2 }
                    elseif ($ValueOptions -and $j + 1 -lt $Arguments.Count -and $Arguments[$j + 1] -notin $Verbs -and -not $Arguments[$j + 1].StartsWith('-')) { $j += 2 }
                    else { $j++ }
                    continue
                }
                return @{ Verb = $a.ToLowerInvariant(); Rest = @($Arguments | Select-Object -Skip ($j + 1) | Where-Object { -not $_.StartsWith('-') }) }
            }
        }

        $isAction = $false; $needContext = $null; $needPlan = $false; $destroy = $false; $wide = $false
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

            if ($s.Text -match $hookMark) { return $stateDeny }
            if ($program -eq 'claude' -and @($arguments | Where-Object { $_ -cin '--resume', '--continue', '-r', '-c' })) { return $stateDeny }
            if ($program -in $shells) { $wide = $true }

            switch ($program) {
                'kubectl' {
                    $v = Get-Verb $arguments @('-n', '--namespace', '--context', '--kubeconfig', '--cluster', '--user', '-s', '--server', '--as', '--as-group', '--token', '--request-timeout') $kubeVerbs
                    if (-not $v -or $v.Verb -notin $kubeVerbs) { break }
                    $sub = @{ rollout = 'restart|undo|pause|resume'; auth = 'reconcile'; certificate = 'approve|deny' }[$v.Verb]
                    if ($sub -and $v.Rest[0] -notmatch "^($sub)$") { break }
                    $isAction = $true
                    if (-not @($arguments | Where-Object { $_ -eq '--context' -or $_ -like '--context=?*' })) { $needContext = 'kubectl --context <cluster>' }
                }
                'helm' {
                    $v = Get-Verb $arguments @('-n', '--namespace', '--kube-context', '--kubeconfig', '--kube-apiserver', '--kube-as-user', '--kube-token') $helmVerbs
                    if (-not $v -or $v.Verb -notin $helmVerbs) { break }
                    $isAction = $true
                    if (-not @($arguments | Where-Object { $_ -eq '--kube-context' -or $_ -like '--kube-context=?*' })) { $needContext = 'helm --kube-context <cluster>' }
                }
                { $_ -in 'tofu', 'terraform' } {
                    $v = Get-Verb $arguments @() $tofuVerbs
                    if (-not $v) { break }
                    if ($v.Verb -eq 'destroy') { $destroy = $true; break }
                    if ($v.Verb -notin $tofuVerbs) { break }
                    if ($v.Verb -eq 'state' -and $v.Rest[0] -notin 'rm', 'mv', 'push', 'replace-provider') { break }
                    if ($v.Verb -eq 'workspace' -and $v.Rest[0] -ne 'delete') { break }
                    $isAction = $true
                    if ($v.Verb -eq 'apply' -and -not @($v.Rest | Where-Object { $_ -match '\.tfplan$' -and $_ -notmatch '=' })) { $needPlan = $true }
                }
                'ansible-playbook' { if (-not @($arguments | Where-Object { $_ -eq '--check' -or $_ -ceq '-C' })) { $isAction = $true } }
                { $_ -in 'ansible-pull', 'ansible-console' } { $isAction = $true }
                'ansible' { if ($arguments.Count -and -not @($arguments | Where-Object { $_ -in '--version', '-h', '--help' })) { $isAction = $true } }
                'argocd' { if (Test-AnyMatch $s.Text @($loose[4])) { $isAction = $true } }
                { $_ -in 'ansible-lint', 'ansible-galaxy', 'ansible-inventory', 'ansible-doc', 'ansible-config' } { }
                default { if (Test-AnyMatch $s.Text $loose) { $isAction = $true } }
            }
        }
        # Un texte envoyé à un shell (`echo '…' | bash`) se lit en entier.
        if ($wide -and $segments.Count -gt 1) {
            if ($raw -match $hookMark) { return $stateDeny }
            if (Test-AnyMatch $raw $loose) { $isAction = $true }
        }

        if ($destroy) {
            return @{ Decision = 'deny'; Reason = "pas de tofu destroy direct : tofu plan -destroy -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($needPlan) {
            return @{ Decision = 'deny'; Reason = "tofu apply se lance sur un plan enregistré : tofu plan -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($needContext) {
            return @{ Decision = 'deny'; Reason = "nommer le cluster visé : $needContext. Le contexte courant peut être le mauvais cluster." }
        }
        if (-not $isAction) { return }

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
