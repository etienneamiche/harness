# Changelog

Format : [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/). Versions : [semver](https://semver.org/lang/fr/).

## [Non publié]

## [0.3.0] - 2026-11-11

Les skills du workflow (phase 4 de la roadmap).

### Ajouté
- **Skill `/audit-pr`** : la revue complète d'une PR avant sa fusion, confiée à `auditor`, qui publie son verdict en commentaire. Le skill distingue le premier passage de la revue après corrections, prépare la copie locale, et propose un mode essai qui ne publie rien. Son guide (`references/review-guide.md`) fixe la méthode, la gravité, le format du commentaire et la publication du marqueur.
- **Skill `/ship`** : envoie le travail terminé d'une branche en revue. La session principale contrôle les fichiers (secrets et fichiers de travail écartés), les tests et le lint, puis rédige le commit et la PR (modèle de PR, critères de l'issue) ; `git-ops` commite, pousse, ouvre ou met à jour la PR et passe la carte en « En revue ». Le skill refuse de commiter sur `main` ou `develop`, signale qu'un nouveau commit annule une approbation `auditor`, et propose un mode essai qui ne publie rien.
- **Skill `/review`** : relit le travail en cours pendant le développement (commits de la branche, modifications non commitées, nouveaux fichiers), avec `reviewer`. La session vérifie chaque constat dans le code, écarte les faux positifs en le disant, puis rend « À corriger » / « À voir » avec `fichier:ligne`. Les critères de l'issue liée sont transmis, et un gros diff est découpé. Rien n'est modifié ni publié.
- **Skill `/feature`** : mène une issue jusqu'au travail prêt à envoyer. Sans critères d'acceptation, il les demande. `git-ops` crée la branche, sans qu'elle suive la base, et passe la carte en « En cours ». La session fait valider un plan court, `dev` implémente le code et les tests jusqu'au vert, puis `/review` (deux tours de corrections au plus) et `/lint` passent. Le skill s'arrête avant `/ship` et le propose. Mode essai sans geste GitHub.
- **Skill `/lint`** : fait passer au vert le lint, le format et le typecheck avec `linter`, par `scripts/lint.ps1` ou les vérifications des modules. Les corrections à la main se limitent aux fichiers de la branche. La session contrôle ensuite le diff de `linter`, puis relance les tests : elle refuse et fait restaurer toute suppression d'avertissement et tout changement de comportement. Rien n'est commité.
- **Skill `/idea`** : transforme une idée en issue `feature`, carte en « Idée ». La session cherche d'abord les issues ouvertes proches et propose de compléter un doublon plutôt que d'en créer un. Elle ne pose ensuite que les questions qui manquent, en un seul message, et attend la réponse. Au-delà d'une PR, elle propose un découpage. Le brouillon suit le modèle d'issue `feature` et l'utilisateur le valide, puis `git-ops` crée l'issue et place la carte. Un bug est renvoyé vers le modèle `bug`. Mode essai sans geste GitHub.
- **Skill `/spec`** : rend une issue prête à développer. `architect` rédige les critères d'acceptation vérifiables, les impacts, un plan court avec sa taille et le hors-périmètre, sans rien écrire dans le dépôt. Un choix structurant donne 2 ou 3 options que l'utilisateur tranche, et l'ADR devient un critère de l'issue. Une issue déjà en cours (branche ou PR) demande l'accord de l'utilisateur. Après validation, `git-ops` met à jour l'issue, en gardant le besoin d'origine, et passe la carte en « Prêt ». Mode essai sans geste GitHub.
- **Skill `/release`** et **`cliff.toml`** (types `app`, `game`, `sandbox` et `template`) : publie une version en local. git-cliff propose la version et rédige la section du CHANGELOG depuis les commits, et l'utilisateur les valide. Les tests, le lint, `ARCHITECTURE.md` (par `cartographer`) et le milestone sont contrôlés avant. `git-ops` ouvre la branche `release/x.y.z`, la PR passe par `/audit-pr`, puis `git-ops` fusionne, tague `vX.Y.Z` et crée la release GitHub. En gitflow, `main` est ensuite reporté dans `develop` par une PR. Le skill gère aussi les hotfix et la reprise d'une release commencée. Mode essai sans geste GitHub. L'image et la PR de version dans `homelab` attendent la phase 10.
- **Skill `/retro`** : la rétrospective du travail récent, appuyée sur des preuves. Un script en lecture seule relève dans les transcripts du projet les refus de hooks, les commandes qui échouent plusieurs fois et les corrections de l'utilisateur, ainsi que les constats d'`auditor` des PR fusionnées sur la période. La session écarte le bruit et range chaque constat : une règle d'`AGENTS.md` (par une issue du projet, puis `/feature`), une issue `harness-update` sur `harness`, ou une issue pour `/evolve` sur `services`. L'utilisateur valide, puis `git-ops` crée les issues. Aucun fichier du dépôt n'est modifié. Le script ne lit que les messages du projet (d'après leur dossier de travail), compte une session reprise une seule fois et masque les secrets ; des autotests le couvrent. Mode essai sans geste GitHub.
- **Skill `/doctor`** : lance le doctor du projet et explique chaque écart : la cause, vérifiée par un contrôle ciblé (`git log` et `git diff` d'un fichier du harness modifié, `settings.json`, autotest relancé seul), l'effet concret et la correction. Les corrections sont rangées en trois groupes : sans risque (`-Fix`, lancé après accord, puis le doctor relancé), à la main de l'utilisateur (restaurer un fichier du harness, installer un outil, mettre à jour), destructrices (`copier recopy`, jamais lancé). Les fichiers du harness modifiés sont présentés en premier. Une modification voulue d'un fichier du harness se remonte par une issue `harness-update`. Dans un projet du harness, `/doctor` désigne ce skill et masque la commande `/doctor` intégrée à Claude Code, qui vérifie et répare l'installation de Claude Code. `claude doctor`, dans un terminal, en fait la vérification sans les réparations.
- **Skill `/help-harness`** : l'expert du harness installé, qui répond à partir des fichiers de la version du projet et ne modifie rien. Il explique un refus de hook : la règle et le motif en cause (le hook rejoué sur une entrée écrite dans un fichier), la façon légitime de faire, et s'il s'agit d'un faux positif ou d'un refus qui joue son rôle. Il dit ce que coûtent `HARNESS_HOOK_PROFILE` et `HARNESS_DISABLED_HOOKS`, sans jamais les régler. Il donne ce qu'apporte une version (le CHANGELOG du dépôt source, lu au tag) et la procédure de mise à jour, sans la lancer. Un besoin propre au projet devient une règle d'`AGENTS.md` (par une issue, puis `/feature`), un besoin commun une issue `harness-update` créée par `git-ops` après accord. À la racine `services`, il couvre aussi les scripts de l'écosystème.
- **Skill `/homelab`** (racine `services` seulement) : répond sur l'infra du homelab à partir de `homelab/docs/`. Chaque fait cite son fichier, sa section et sa date. Le skill sépare ce qui est fait de ce qui est prévu (phases H0 à H5), fait primer les décisions datées et signale les docs qui se contredisent ou les renvois cassés. Il ne lance aucune commande vers l'infra : pour l'état réel, il dit ce qu'affirment les docs et donne la commande à lancer soi-même. Les détails d'infra restent dans la session : un problème devient une issue de `homelab`, et une issue sur un dépôt public est rédigée sans adresse ni nom d'hôte.
- **Skill `/project-idea`** (racine `services` seulement) : tient les idées de nouveaux projets du dépôt `project-ideas`. Il note une idée en une phrase par `scripts/idea.ps1 -NoCommit` et signale les idées proches. Il crée la page d'une idée après quelques questions, d'après `_template.md`, et passe une idée `brute` en `décrite`. Il change un statut (`retenue`, `en pause`, `abandonnée` avec sa raison). `lancée` reste à `/start-project`. `git-ops` commite seulement les fichiers touchés et pousse sur `main`. À la racine, `doc-sprawl` laisse passer `IDEAS.md`, `_template.md` et `ideas/` de `project-ideas/`.
- **`.harness/tools/board.ps1`**, réservé à `git-ops` : place la carte d'une issue dans une colonne du Project « services », et l'y ajoute si besoin. Les écritures `gh project` sont réservées à `git-ops` elles aussi.
- **Modèles d'issue et de PR** (`.github/`) : `feature` et `bug`, avec leurs critères d'acceptation, et un modèle de PR que remplit `/ship`.

### Corrigé
- **`doctor -Fix` ne réécrit plus le manifeste** en réparant `.gitignore` : `post-install.ps1` prend `-SkipManifest`, que le doctor lui passe. Un fichier du harness modifié restait sinon invisible au doctor suivant. Un autotest le vérifie.
- **`doctor -Fix` respecte `HARNESS_SKIP_PLUGINS`** : il installait quand même les plugins manquants, et `claude plugin install` réécrit `.claude/settings.json` (harness#4), que le doctor voyait ensuite comme un fichier du harness modifié.
- `git-guard` ne prend plus le texte d'un message de commit pour des options : un corps qui cite `-Days` ou `--no-verify` n'est plus refusé comme un `git commit -a`. `git commit --all` est refusé, comme `-a`.
- `git-guard` ne prend plus `git merge-base` ni `git merge-tree`, des lectures, pour une fusion réservée à `git-ops`.
- `git-guard` voit les interdits confiés à un autre programme (`bash -c '…'`, `pwsh -Command`, `iex`, `trap`, `awk`, un tube ou un heredoc vers un shell). La commande est découpée hors des chaînes, et seul le texte d'un programme identifié échappe à l'analyse : les options de texte de `git`, de `gh` et de `merge-pr.ps1`, selon la sous-commande, recherches comprises (`git log -S`, `--grep`, `gh issue list --search`), une variable de texte seule dans sa commande (`$body = …`, `msg='…'`), et ce qui part vers `-F -` ou dans un fichier `.md` ou `.txt`. Ailleurs, une chaîne qui cite un interdit est refusée, avec un motif qui dit où écrire ou chercher ce texte : `grep 'git add -A' fichier` passe par l'outil Grep. Encore possible : `$body = '…'; iex $body`, un fichier `.md` écrit puis exécuté, et la sortie d'une commande envoyée à un shell (`git commit -m '…' | bash`). `(git add -A)`, `$(git add .)`, `git add -A>x`, `& { git add -A}` et `git add ./` sont refusés, comme `git add -A`.
- `destructive-guard` retient chaque commande destructive confirmée dans une session, et plus seulement la première : les suivantes étaient refusées à chaque essai. Un état écrit par l'ancienne version ne bloque pas ; une commande déjà confirmée est refusée une fois de plus.
- `Get-Help` affiche enfin l'aide des outils du harness (`doctor`, `post-install`, `board`, `merge-pr`, `write-manifest`, `tools/test.ps1`) : leur bloc d'aide, collé à la ligne `#Requires`, n'était pas reconnu. `write-manifest.ps1` reçoit une aide, et un autotest vérifie celle de chaque outil.

### Modifié
- Convention de branches : `chore/harness-vX.Y.Z` pour une mise à jour du harness.
- La taille cible d'une PR passe de 400 à 1 500 lignes modifiées, hors fichiers générés et lockfiles : conventions, `/feature`, `/ship`, guide de `/audit-pr` et modèle d'issue `feature`.
- `auditor` renvoie au guide de `/audit-pr` pour la méthode et le format, et ne garde que les règles non négociables.

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
- `git-ops` : messages de commit en anglais ; le message du commit fusionné est donné explicitement, en anglais (le titre de la PR reste en français).
- **La fusion passe par `.harness/tools/merge-pr.ps1`**, réservé à `git-ops` : paramètres typés, revue `auditor` vérifiée, fusion du seul commit revu (`--match-head-commit`), squash avec message obligatoire ou `merge` pour une release. `git-guard` refuse tout `gh pr merge` direct.
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

La deuxième revue a trouvé deux défauts introduits par ces corrections, eux aussi corrigés :
- **`git-guard` pouvait vérifier la revue d'une autre PR** : il prenait le premier nombre de la commande, y compris dans le texte de `--subject`. La troisième revue a montré qu'aucune analyse de la ligne de commande ne serait fiable (échappements, commandes enchaînées, `--repo`) : la fusion directe est désormais interdite, au profit de `merge-pr.ps1` ;
- **un test lançait le vrai hook `Stop` sur le projet réel** : il tourne désormais dans une copie jetable du harness.

La quatrième revue a éprouvé `merge-pr.ps1` (18 commandes de contournement essayées sur le vrai hook) et relevé cinq points, corrigés :
- seul le marqueur de revue posé par **le compte GitHub courant** compte (les dépôts sont publics), et `git-guard` refuse le marqueur à tout autre agent qu'`auditor`, y compris par `--body-file` ;
- la règle `homelab` se juge sur l'URL de la PR lue (une variable `GH_REPO` ne la contourne plus), et le dépôt est imposé à `gh` ;
- la branche n'est supprimée qu'en squash (une `release/*` doit encore aller dans `develop`) ;
- `git-guard` retire les options globales de git (`-C`, `-c`, `--git-dir`…) avant l'analyse ;
- toute écriture par `gh api` (`--method=`, `-f`, `-F`, `--input`, `graphql`) est réservée à l'utilisateur.

La cinquième revue a relevé que `-R` / `--repo` de `gh` peut se placer avant la sous-commande (`gh pr -R x merge`) : il est désormais retiré avant l'analyse, comme les options globales de git. Dans la même passe :
- `git -p` / `--paginate` sont vus, et un alias git défini en ligne (`-c alias.…`) est refusé ;
- `gh api -X GET … -f` (une lecture) n'est plus refusé, et un champ collé (`-fclé=valeur`) est vu.

Ce qu'aucun hook ne peut fermer (mot cité ou découpé, alias, `curl` avec un jeton) relève d'une protection côté GitHub : voir la roadmap de `services`, phase 10.

En les corrigeant, un troisième défaut est apparu : **le doctor affichait vert alors qu'un fichier de tests ne pouvait pas s'exécuter**. Il signale désormais tout fichier ou bloc de tests en erreur.

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
