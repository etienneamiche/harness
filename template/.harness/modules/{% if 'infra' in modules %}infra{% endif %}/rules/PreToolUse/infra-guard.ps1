# infra-guard (module infra) : aucune action sur l'infra sans l'accord de l'utilisateur.
# Une action est refusée avec un code ; elle passe une seule fois, relancée à l'identique,
# après que l'utilisateur a écrit `ok infra <code>` dans le chat (règle infra-approval).
# Un agent ne peut pas donner cet accord : ses outils ne passent pas par UserPromptSubmit.
# Au mieux de ses moyens : une action lancée par un détour (ssh, script) n'est pas reconnue.
@{
    Name     = 'infra-guard'
    Event    = 'PreToolUse'
    Tools    = 'Bash|PowerShell'
    Profiles = 'minimal', 'standard', 'strict'
    Kind     = 'guard'
    Run      = {
        param($ctx)
        $cmd = (Get-Value $ctx.ToolInput 'command' '').Trim()
        $seg = '[^;&|\n]*'

        # Le code d'accord ne s'écrit que dans le chat : une commande qui le cite essaie de le rejouer.
        if ($cmd -match '\bok\s+infra\s+\d{4}\b') {
            return @{ Decision = 'deny'; Reason = "l'accord pour une action sur l'infra se donne par l'utilisateur, dans le chat. Une commande ne le cite pas." }
        }

        $tofu = "\b(tofu|terraform)(\.exe)?['`"]?(\s+-\S+)*\s+"
        if ($cmd -match "$($tofu)destroy\b") {
            return @{ Decision = 'deny'; Reason = "pas de tofu destroy direct : tofu plan -destroy -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }
        if ($cmd -match "$($tofu)apply\b" -and $cmd -notmatch "$($tofu)apply\b$seg\s\S+\.tfplan['`"]?(\s|$)") {
            return @{ Decision = 'deny'; Reason = "tofu apply se lance sur un plan enregistré : tofu plan -out=<périmètre>.tfplan, montrer le plan à l'utilisateur, puis tofu apply <périmètre>.tfplan." }
        }

        $kubectlAction = "\bkubectl(\.exe)?\b$seg\s(apply|create|delete|replace|patch|edit|scale|rollout\s+(restart|undo|pause|resume)|drain|cordon|uncordon|label|annotate|taint|set|autoscale|expose|run|exec|cp|debug)\b"
        $helmAction = "\bhelm(\.exe)?\b$seg\s(install|upgrade|rollback|uninstall|delete)\b"
        if (($cmd -match $kubectlAction -and $cmd -notmatch '\s--context[=\s]\S') -or ($cmd -match $helmAction -and $cmd -notmatch '\s--kube-context[=\s]\S')) {
            return @{ Decision = 'deny'; Reason = 'nommer le cluster visé : kubectl --context <cluster>, helm --kube-context <cluster>. Le contexte courant peut être le mauvais cluster.' }
        }

        $actions = @(
            "$tofu(apply|import|taint|untaint|force-unlock|state\s+(rm|mv|push|replace-provider))\b",
            "\bansible-playbook\b(?!$seg\s(--check|-C)\b)",
            "\bansible(\.exe)?(?![-\w])(?!\s+--version\b)\s+\S",
            $kubectlAction,
            $helmAction,
            "\bargocd(\.exe)?\b$seg\sapp\s+(sync|delete|set|unset|patch|rollback|create|terminate-op)\b"
        )
        if (-not (Test-AnyMatch $cmd $actions)) { return }

        # Accord donné pour cette commande-là : il sert une fois.
        $state = Get-HarnessStatePath $ctx.SessionId 'infra'
        $data = if (Test-Path $state) { Get-Content $state -Raw | ConvertFrom-Json -AsHashtable } else { $null }
        if (-not $data) { $data = @{} }
        $pending = $data['pending'] ?? @{}
        $approved = @($data['approved'] ?? @())
        $key = Get-StringHash $cmd
        if ($approved -contains $key) {
            $data['approved'] = @($approved | Where-Object { $_ -ne $key })
            ConvertTo-Json -InputObject $data -Compress | Set-Content $state
            return
        }

        $code = @($pending.Keys | Where-Object { $pending[$_] -eq $key }) | Select-Object -First 1
        if (-not $code) {
            do { $code = '{0:D4}' -f (Get-Random -Minimum 0 -Maximum 10000) } while ($pending.ContainsKey($code))
            $pending[$code] = $key
            $data['pending'] = $pending
            $data['approved'] = $approved
            ConvertTo-Json -InputObject $data -Compress | Set-Content $state
        }
        @{ Decision = 'deny'; Reason = @"
action sur l'infra, qui demande l'accord de l'utilisateur. Avant de la relancer à l'identique :
1. montre-lui la commande exacte et ce qu'elle va changer (le plan, le diff, --check --diff) ;
2. donne en une ligne la façon de revenir en arrière ;
3. demande-lui d'écrire dans le chat : ok infra $code
Cet accord vaut pour cette commande, une seule fois. Ne l'écris pas toi-même.
"@ }
    }
}
