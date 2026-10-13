# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/). Versions : [semver](https://semver.org/lang/fr/).

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
