# harness

Le cadre de travail commun à tous les projets de l'écosystème `services` : conventions pour les agents, subagents à modèle imposé, hooks de garde, protection des secrets, doctor.

C'est un **template [Copier](https://copier.readthedocs.io) versionné**. Chaque projet sait quelle version il a reçue (`.copier-answers.harness.yml`) et peut être mis à jour sans écraser ses spécificités.

## Installer dans un projet

```powershell
copier copy --trust gh:etienneamiche/harness <dossier-du-projet>
```

`--trust` est nécessaire : l'installation lance `.harness/tools/post-install.ps1`, qui active le hook Git `pre-commit`, complète `.gitignore`, installe les plugins Claude Code du projet et écrit le manifeste.

Questions posées : nom, description, **type de dépôt** (`app`, `game`, `sandbox`, `root`, `ideas`, `libs`, `template`, `infra`), **modules** et **profil des hooks** (`minimal`, `standard`, `strict`).

## Modules

| Module | Pour | Apporte |
|---|---|---|
| `react` | Un front | Conventions React, config Biome, vérifications Biome + `tsc`, plugin `typescript-lsp` |
| `dotnet` | Un backend .NET | Conventions .NET, `analyzers.globalconfig`, vérifications `dotnet format` + build + numéros de migration, subagent `db-ops`, skills `dotnet-webapi` et `optimizing-ef-core-queries`, plugin `csharp-lsp` |
| `python` | Un petit module Python | Conventions Python, vérifications ruff + pyright, plugin `pyright-lsp` |
| `game` | Un jeu multijoueur (avec `react` et `dotnet`) | Conventions jeu : serveur qui fait autorité, règles pures, salles, sauvegardes |

Un module vit dans `template/.harness/modules/{% if '<nom>' in modules %}<nom>{% endif %}/` (le nom conditionnel fait qu'il n'est créé que si le module est choisi) : `conventions.md` (importé par `core.md`), `module.json` (vérifications de fin de tour `stopChecks`, blocs structurels `structural`), et ses fichiers de configuration.

**Ajouter une techno**, c'est ajouter un module, sans toucher aux hooks ni au dispatcher. Il faut aussi :
- l'ajouter aux `choices` de la question `modules` dans `copier.yml`, et à son `validator` s'il est incompatible avec un autre ;
- déclarer son plugin LSP dans `template/.claude/settings.json.jinja`, s'il en a un ;
- l'ajouter à un scénario de `tools/test.ps1`.

Combinaisons refusées par Copier : `game` sans `dotnet` et `react` ; `python` avec `dotnet` (un dépôt n'a qu'un seul backend).

## Mettre à jour un projet

```powershell
copier update --trust           # dans le dossier du projet
.harness/tools/doctor.ps1        # vérifier le résultat
```

## Ce que le harness installe

```
CLAUDE.md                    @AGENTS.md
AGENTS.md                    au projet (jamais écrasé), importe .harness/agents/core.md
ARCHITECTURE.md              au projet (jamais écrasé)
.gitattributes               fins de ligne (prioritaire sur core.autocrlf)
.gitleaks.toml               règles gitleaks par défaut + exclusion du manifeste
.claude/settings.json        modèle, permissions, hooks, plugins, claudeMdExcludes
.claude/agents/              8 subagents à modèle imposé
.claude/skills/              skills du harness (/review, /lint, /ship, /audit-pr), plus ceux des modules
.github/                     modèles d'issue (feature, bug) et de PR
.harness/
  agents/core.md             conventions communes
  harness.json               configuration des règles, selon le type de dépôt
  hooks/dispatch.ps1         point d'entrée unique des hooks
  hooks/rules/<Événement>/   une règle par fichier
  githooks/pre-commit        gitleaks + noms de fichiers secrets
  tools/                     post-install, doctor, manifeste, merge-pr (seul chemin de fusion), board (carte sur le Project)
  tests/                     autotests Pester des hooks
```

## Subagents

| Agent | Modèle | Rôle |
|---|---|---|
| `dev` | Opus | Écrire le code et ses tests |
| `architect` | Opus | Spécification, architecture, roadmap |
| `auditor` | Opus | Revue complète avant fusion (`/audit-pr`), audits |
| `explorer` | Haiku | Explorer le code |
| `linter` | Haiku | Nettoyer le lint (`/lint`) |
| `git-ops` | Haiku | Toutes les écritures Git et GitHub |
| `reviewer` | Haiku | Relire un diff (`/review`) |
| `cartographer` | Haiku | Résumer l'architecture existante |

## Règles des hooks

| Règle | Événement | Profils | Effet |
|---|---|---|---|
| `model-guard` | PreToolUse | tous | Agents hors liste blanche refusés ; paramètre `model` refusé |
| `git-guard` | PreToolUse | tous | Écritures Git/GitHub réservées à `git-ops` ; worktree, rebase -i, push forcé, `--no-verify`, `git add -A` interdits ; branches protégées ; numéro d'issue ; revue `auditor` avant fusion |
| `secret-guard` | PreToolUse | tous | Fichiers et commandes qui exposeraient un secret |
| `destructive-guard` | PreToolUse | standard, strict | Commande destructive refusée au premier essai |
| `config-protection` | PreToolUse | standard, strict | Configs de lint, harness, CI, `.gitignore`, SOPS protégés |
| `secret-prompt` | UserPromptSubmit | tous | Message contenant un jeton bloqué |
| `doc-sprawl` | PostToolUse | standard, strict | Markdown écrit hors de `docs/` signalé |
| `structural-watch` | PostToolUse | standard, strict | Bloc venu d'un template modifié → `/upstream` |
| `stop-checks` | Stop | standard, strict | Vérifications des modules ; traces de debug (strict) |
| `session-info` | SessionStart | tous | Version du harness, index codegraph |

Réglages à la volée : `HARNESS_HOOK_PROFILE=minimal|standard|strict`, `HARNESS_DISABLED_HOOKS=regle1,regle2`.

**Latence.** Chaque hook lance `pwsh` : ~220 ms incompressibles, ~390 ms au total par appel. Les hooks ne sont branchés que sur les outils où une règle s'applique (`Agent`, `Bash`, `PowerShell`, `Edit`, `Write`). `Read`, l'outil le plus appelé, est couvert nativement par `permissions.deny`.

## Ajouter une règle

Un fichier `.ps1` dans `template/.harness/hooks/rules/<Événement>/`, qui renvoie :

```powershell
@{
    Name     = 'ma-regle'
    Event    = 'PreToolUse'
    Tools    = 'Bash|PowerShell'          # facultatif : outils concernés
    Profiles = 'standard', 'strict'
    Kind     = 'guard'                    # guard : échoue fermé ; info : échoue ouvert
    Run      = { param($ctx) if (...) { @{ Decision = 'deny'; Reason = '...' } } }
}
```

Décisions possibles : `deny` (PreToolUse), `block` (UserPromptSubmit, Stop), `context` (information ajoutée au contexte de l'agent). Les modules par techno ajoutent leurs règles dans `.harness/modules/<nom>/rules/<Événement>/`.

Toute règle nouvelle s'accompagne de ses tests dans `template/.harness/tests/Hooks.Tests.ps1`.

## Développer le harness

```powershell
./tools/test.ps1                  # génère un projet de chaque type, puis doctor -Deep dans chacun
./tools/test.ps1 -Kind sandbox -Keep
```

Versions : semver, tags `vX.Y.Z` sur `main`, notes dans [CHANGELOG.md](CHANGELOG.md).
