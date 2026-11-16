# infra-guard (module infra) : aucune action sur l'infra sans l'accord de l'utilisateur.
# Une action est refusée avec un code ; elle passe une seule fois, relancée à l'identique,
# après que l'utilisateur a écrit `ok infra <code>` dans le chat (règle infra-approval).
# Garde au mieux de ses moyens : l'agent tourne sous le même compte que l'utilisateur. La règle
# refuse ce qui toucherait l'état des accords ou rejouerait un message, mais un détour assez
# déterminé (ssh, script, alias) n'est pas reconnu.
@{
    Name     = 'infra-guard'
    Event    = 'PreToolUse'
    Tools    = 'Bash|PowerShell|Edit|Write|MultiEdit|NotebookEdit'
    Profiles = 'minimal', 'standard', 'strict'
    Kind     = 'guard'
    Run      = {
        param($ctx)
        $stateDeny = @{ Decision = 'deny'; Reason = "l'état des accords d'infra et les messages de l'utilisateur ne se touchent pas : seul l'utilisateur donne un accord, en écrivant ok infra <code> dans le chat." }
        if ($ctx.ToolName -notin 'Bash', 'PowerShell') {
            $path = Get-Value $ctx.ToolInput 'file_path' (Get-Value $ctx.ToolInput 'notebook_path' '')
            if ($path -match 'claude-harness') { return $stateDeny }
            return
        }
        $raw = (Get-Value $ctx.ToolInput 'command' '').Trim()

        # Ce qui donnerait un accord sans l'utilisateur : citer un code, l'état des accords, l'événement
        # des messages, ou reprendre une session (claude --resume rejouerait un message dans celle-ci).
        if ($raw -match '\bok\s+infra\s+\d{4}\b' -or $raw -match 'claude-harness|\.infra\.json|UserPromptSubmit|infra-approval' -or
            $raw -cmatch '\bclaude(\.exe|\.cmd)?\b[^;&|\n]*\s(--resume|--continue|-r|-c)\b') { return $stateDeny }

        # Le texte cité (message de commit, motif de recherche, echo) ne compte pas, sauf celui confié
        # à un shell (`bash -c "…"`, `pwsh -Command "…"`) ou un programme cité (`& "C:\…\tofu.exe"`).
        $cmd = [regex]::Replace($raw, '(?<keep>(^|[;&|(\n]|\s-c|\s-Command|\s--command|&)\s*)?([''"])(.*?)\2', {
            param($m) if ($m.Groups['keep'].Success) { $m.Value } else { ' _ ' } })
        $cmd = $cmd -replace '(^|\s)#[^\n]*', ''

        # Un programme en position de commande : début de segment, après wsl, sudo, k3s, &, ou dans un shell.
        $at = '(?<=((^|[;&|(\n{])\s*(&\s*)?|\b(wsl|sudo|exec|env|time|k3s)(\s+-\S+(\s+[^-\s]\S*)?)*\s+|(\s-c|\s-Command|\s--command)\s+[''"]\s*)[''"]?(\S*[\\/])?)'
        $opts = '((\s+--?[\w-]+=\S+)|(\s+(-n|--namespace|--context|--kube-context|--kubeconfig|--cluster|--user|-s|--server|--as|--kube-namespace)\s+\S+)|(\s+--?[\w-]+))*'
        $tofu = "$at(tofu|terraform)(\.exe)?['`"]?(\s+-\S+)*\s+"
        $kubectlAction = "$at(kubectl)(\.exe)?['`"]?$opts\s+(apply|create|delete|replace|patch|edit|scale|rollout\s+(restart|undo|pause|resume)|drain|cordon|uncordon|label|annotate|taint|set|autoscale|expose|run|exec|cp|debug|auth\s+reconcile|certificate\s+(approve|deny))(\s|$)[^;&|\n]*"
        $helmAction = "$at(helm)(\.exe)?['`"]?$opts\s+(install|upgrade|rollback|uninstall|delete|test)(\s|$)[^;&|\n]*"

        if ($cmd -match "$($tofu)destroy\b") {
            return @{ Decision = 'deny'; Reason = "pas de tofu destroy direct : tofu plan -destroy -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        $apply = [regex]::Match($cmd, "$($tofu)apply\b[^;&|\n]*", 'IgnoreCase')
        if ($apply.Success -and $apply.Value -notmatch '\s[^\s=]+\.tfplan[''"]?(\s|$)') {
            return @{ Decision = 'deny'; Reason = "tofu apply se lance sur un plan enregistré : tofu plan -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        $k = [regex]::Match($cmd, $kubectlAction, 'IgnoreCase')
        $h = [regex]::Match($cmd, $helmAction, 'IgnoreCase')
        if (($k.Success -and $k.Value -notmatch '\s--context[=\s]\S') -or ($h.Success -and $h.Value -notmatch '\s--kube-context[=\s]\S')) {
            return @{ Decision = 'deny'; Reason = 'nommer le cluster visé : kubectl --context <cluster>, helm --kube-context <cluster>. Le contexte courant peut être le mauvais cluster.' }
        }

        $actions = @(
            "$tofu(apply|import|taint|untaint|force-unlock|refresh|test|state\s+(rm|mv|push|replace-provider)|workspace\s+delete)\b",
            "$at(ansible-playbook)\b(?![^;&|\n]*\s(--check|(?-i:-C))(\s|$))",
            "$at(ansible-pull)\b",
            "$at(ansible)(\.exe)?(?![-\w])(?!\s+--version\b)\s+\S",
            $kubectlAction,
            $helmAction,
            "$at(argocd)(\.exe)?\b[^;&|\n]*\s(app\s+(sync|delete|set|unset|patch|rollback|create|terminate-op|actions\s+run)|appset\s+(create|delete)|proj\s+(create|delete)|cluster\s+(add|rm))\b"
        )
        if (-not (Test-AnyMatch $cmd $actions)) { return }

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

        $code = @($pending.Keys | Where-Object { $pending[$_] -eq $key }) | Select-Object -First 1
        if (-not $code) {
            do { $code = '{0:D4}' -f [Security.Cryptography.RandomNumberGenerator]::GetInt32(10000) } while ($pending.ContainsKey($code))
            $pending[$code] = $key
            $data['pending'] = $pending
            $data['approved'] = $approved
            ConvertTo-Json -InputObject $data -Compress | Set-Content $state
        }
        @{ Decision = 'deny'; Reason = @"
action sur l'infra, qui demande l'accord de l'utilisateur. Avant de la relancer à l'identique :
1. montre-lui la commande exacte et ce qu'elle va changer (le plan, le diff, --check --diff) ;
2. donne en une ligne la façon de revenir en arrière ;
3. demande-lui d'écrire, seul dans son message : ok infra $code
Cet accord vaut pour cette commande, une seule fois. Ne l'écris jamais toi-même, ni dans une commande.
"@ }
    }
}
