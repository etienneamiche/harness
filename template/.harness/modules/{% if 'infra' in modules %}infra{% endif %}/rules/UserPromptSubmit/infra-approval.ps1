# infra-approval (module infra) : l'utilisateur autorise une action sur l'infra en écrivant
# `ok infra <code>`, le code donné par infra-guard. L'accord vaut pour la commande de ce code,
# une seule fois. Seul un message de l'utilisateur passe par cet événement.
@{
    Name     = 'infra-approval'
    Event    = 'UserPromptSubmit'
    Profiles = 'minimal', 'standard', 'strict'
    Kind     = 'info'
    Run      = {
        param($ctx)
        $prompt = Get-Value $ctx.Input 'prompt' ''
        $codes = @([regex]::Matches($prompt, '\bok\s+infra\s+(\d{4})\b', 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value })
        if (-not $codes) { return }

        $state = Get-HarnessStatePath $ctx.SessionId 'infra'
        $data = if (Test-Path $state) { Get-Content $state -Raw | ConvertFrom-Json -AsHashtable } else { $null }
        $pending = if ($data) { $data['pending'] ?? @{} } else { @{} }
        $approved = @(if ($data) { $data['approved'] ?? @() })
        $granted = @(); $unknown = @()
        foreach ($code in $codes) {
            if ($pending.ContainsKey($code)) { $approved += $pending[$code]; $pending.Remove($code); $granted += $code }
            else { $unknown += $code }
        }
        if ($granted) {
            ConvertTo-Json -InputObject @{ pending = $pending; approved = @($approved) } -Compress | Set-Content $state
        }
        $notes = @()
        if ($granted) { $notes += "accord de l'utilisateur enregistré ($($granted -join ', ')) : la commande refusée avec ce code peut être relancée à l'identique, une fois." }
        if ($unknown) { $notes += "code inconnu ou déjà utilisé ($($unknown -join ', ')) : aucune action n'est autorisée par lui." }
        @{ Decision = 'context'; Reason = $notes -join ' ' }
    }
}
