# infra-approval (module infra) : l'utilisateur autorise une action sur l'infra en écrivant
# `ok infra <code>`, le code donné par infra-guard, seul dans son message (une ligne par code).
# L'accord vaut pour la commande de ce code, une seule fois. Un message qui contient autre chose
# (« pas ok infra 1234 », un jeton bloqué par secret-prompt) n'autorise rien.
@{
    Name     = 'infra-approval'
    Event    = 'UserPromptSubmit'
    Profiles = 'minimal', 'standard', 'strict'
    Kind     = 'info'
    Run      = {
        param($ctx)
        $prompt = Get-Value $ctx.Input 'prompt' ''
        if ($prompt -notmatch '\bok\s+infra\s+\d{4}\b') { return }
        $lines = @($prompt -split '\r?\n' | ForEach-Object Trim | Where-Object { $_ })
        if (@($lines | Where-Object { $_ -notmatch '^ok\s+infra\s+\d{4}$' }).Count) {
            return @{ Decision = 'context'; Reason = "le message cite un code d'accord parmi d'autres mots : aucun accord n'est enregistré. Pour autoriser l'action, l'utilisateur écrit seulement ok infra <code>." }
        }
        $codes = @($lines | ForEach-Object { ($_ -split '\s+')[-1] })

        $state = Get-HarnessStatePath $ctx.SessionId 'infra'
        $data = if (Test-Path $state) { Get-Content $state -Raw | ConvertFrom-Json -AsHashtable } else { $null }
        if (-not $data) { $data = @{} }
        $pending = $data['pending'] ?? @{}
        $approved = @($data['approved'] ?? @())
        $granted = @(); $unknown = @()
        foreach ($code in $codes) {
            if ($pending.ContainsKey($code)) { $approved += $pending[$code]; $pending.Remove($code); $granted += $code }
            else { $unknown += $code }
        }
        if ($granted) {
            $data['pending'] = $pending
            $data['approved'] = @($approved)
            ConvertTo-Json -InputObject $data -Compress | Set-Content $state
        }
        $notes = @()
        if ($granted) { $notes += "accord de l'utilisateur enregistré ($($granted -join ', ')) : la commande refusée avec ce code peut être relancée à l'identique, une fois." }
        if ($unknown) { $notes += "code inconnu ou déjà utilisé ($($unknown -join ', ')) : aucune action n'est autorisée par lui." }
        @{ Decision = 'context'; Reason = $notes -join ' ' }
    }
}
