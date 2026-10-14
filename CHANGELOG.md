# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/). Versions : [semver](https://semver.org/lang/fr/).

## [0.2.0] - 2026-10-14

Les conventions de code (phase 3 de la roadmap) et le système de modules.

### Ajouté
- **Système de modules** : question `modules` (`react`, `dotnet`, `python`, `game`). Chaque module installe `.harness/modules/<nom>/` (conventions, vérifications de fin de tour, blocs structurels), importé automatiquement par `core.md`.
- **Conventions communes** (`.harness/agents/conventions.md`) : langues (code et Git en anglais, docs et suivi en français), i18n dès le départ, structure, branches, PR, Conventional Commits, ADR, tests, logs et OpenTelemetry, Problem Details, API tierces via le backend, accessibilité.
- **Module `react`** : Vite, React 19 + React Compiler, TanStack Router et Query, Orval (`*.queries.ts`), react-hook-form + zod, shadcn, react-i18next, options `api` / `auth` / `google` / `realtime`, impersonation, Biome, Vitest + Testing Library + MSW, Playwright + axe.
- **Module `dotnet`** : Controller → Service → Dal / Clients en projets séparés, database-first + migrations SQL DbUp, immuabilité, clients Refit + résilience standard + HybridCache, FluentValidation, `ICurrentUser`, permissions, impersonation, `analyzers.globalconfig`, xUnit v3 + Shouldly + NSubstitute.
- **Module `python`** : petits modules FastAPI, traitements longs (file en processus, état SQLite, progression SSE), exposition `internal`, ruff + pyright.
- **Module `game`** : serveur qui fait autorité, règles pures, salles avec file par salle, reconnexion, sauvegardes de partie versionnées.
- **Subagent `db-ops`** (Haiku), avec le module `dotnet` : migrations locales et scaffolding EF.
- **Skills** adaptés de dotnet/skills (MIT), avec le module `dotnet` : `dotnet-webapi`, `optimizing-ef-core-queries`.
- **Plugins LSP** selon les modules : `csharp-lsp`, `typescript-lsp`, `pyright-lsp`.

### Modifié
- `git-ops` : messages de commit en anglais ; fusion d'une feature en squash avec `--subject` explicite en anglais (le titre de la PR reste en français).
- `git-guard` refuse une fusion en squash sans `--subject`, et toute fusion par rebase.
- `structural-watch` lit aussi les blocs structurels déclarés par les modules.
- `stop-checks` voit les fichiers à l'intérieur d'un dossier non suivi (`--untracked-files=all`).
- Chemins protégés : `backend/Directory.Build.props`, `tsconfig*.json`, `pyrightconfig.json`.
- Copier refuse les combinaisons de modules incohérentes ; `tools/test.ps1` fonctionne par scénarios, dont un scénario invalide qui doit échouer.

### Revue avant fusion
La revue `auditor` de la PR #1 a relevé 7 constats importants et 15 mineurs, corrigés avant la fusion. Les principaux :
- la vérification TypeScript ne compilait rien (`tsc -b`) ;
- les règles de style .NET n'étaient pas évaluées au build (`EnforceCodeStyleInBuild`) ;
- le module `game` contredisait les couches .NET ;
- la licence MIT des skills adaptés était incomplète (fichier `LICENSE` ajouté) ;
- les commits fusionnés auraient été en français.

## [0.1.1] - 2026-10-14

### Corrigé
- Le premier commit d'un projet était refusé par le hook `pre-commit` : gitleaks prenait les empreintes du manifeste (`secret-guard.ps1`, `secret-prompt.ps1`) pour des clés d'API. Ajout d'un `.gitleaks.toml` qui n'exclut que `.harness/manifest.json`.
- Fins de ligne : ajout d'un `.gitattributes` géré par le harness, prioritaire sur `core.autocrlf=true` (réglage par défaut de Git pour Windows).

### Ajouté
- `tools/test.ps1` commite chaque projet généré : le hook `pre-commit` est désormais testé sur les fichiers du harness eux-mêmes.
- Autotest : le manifeste passe le `pre-commit`.

## [0.1.0] - 2026-10-14

Première version : le cœur du harness, sans module de techno.

### Ajouté
- Template Copier avec les types de dépôt `app`, `game`, `sandbox`, `root`, `ideas`, `libs`, `template`, `infra`, et trois profils de hooks.
- `CLAUDE.md` → `AGENTS.md` (au projet) → `.harness/agents/core.md` (conventions communes).
- 8 subagents à modèle imposé : `dev`, `architect`, `auditor` (Opus) ; `explorer`, `linter`, `git-ops`, `reviewer`, `cartographer` (Haiku).
- Dispatcher de hooks PowerShell unique, règles rangées par événement : `model-guard`, `git-guard` (dont la revue `auditor` obligatoire avant fusion), `secret-guard`, `destructive-guard`, `config-protection`, `secret-prompt`, `doc-sprawl`, `structural-watch`, `stop-checks`, `session-info`.
- Hook Git `pre-commit` : gitleaks et noms de fichiers secrets.
- `settings.json` : modèle Opus, `CLAUDE_CODE_SUBAGENT_MODEL=haiku`, `permissions.deny` sur les secrets et `EnterWorktree`, `claudeMdExcludes`, plugin ponytail.
- `post-install.ps1`, `doctor.ps1` (dont `-Fix`, `-Deep`), manifeste d'intégrité.
- Autotests Pester des hooks (87 tests), `tools/test.ps1`.
