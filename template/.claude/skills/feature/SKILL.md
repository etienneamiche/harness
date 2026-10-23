---
name: feature
description: Mène une issue jusqu'au travail prêt à envoyer — branche feature/<n>-… créée par git-ops, carte « En cours », plan court validé, code et tests par dev jusqu'au vert, puis /review et /lint — et s'arrête avant /ship. À utiliser dès que l'utilisateur veut qu'on attaque, implémente, code, développe ou corrige une issue numérotée (« /feature 42 », « attaque l'issue 42 », « on fait la 17 », « implémente le ticket 9 », « corrige le bug #12 », « prends l'issue des exports PDF »), ou reprend une feature en cours sur sa branche. Pas pour une petite retouche sans issue, ni pour commiter et ouvrir la PR (/ship), relire (/review) ou fusionner (/audit-pr).
argument-hint: "<n° d'issue> [essai]"
---

# /feature

Le circuit d'une feature est **`/feature`** → `/review` (autant de fois que nécessaire) → `/ship` → `/audit-pr` → fusion. `/feature` couvre la première partie, de l'issue au travail prêt à envoyer. Il ne publie rien : l'envoi en revue (`/ship`) pousse et ouvre une PR, c'est-à-dire un geste visible, qui se décide avec l'utilisateur.

Chacun son rôle : **`git-ops`** crée la branche et déplace la carte, **`dev`** (Opus) écrit le code et ses tests, `/review` et `/lint` contrôlent. La session principale orchestre : elle lit l'issue, propose le plan, vérifie chaque étape et rend compte.

**Mode essai** : si l'utilisateur demande un essai ou « sans publier », la branche est créée en local, mais la carte ne bouge pas et rien ne part sur GitHub. Ce qui aurait été fait sur GitHub va dans le fichier qu'il indique.

## 1. Lire l'issue

- `gh issue view <n> --json number,title,body,labels,state`. Une issue fermée : s'arrêter et le dire.
- **Les critères d'acceptation** sont la définition de « fini », pour `dev` comme pour `auditor` qui les contrôlera un à un. Sans critères vérifiables, s'arrêter et les demander à l'utilisateur, en proposant éventuellement une formulation, sans écrire de code. Les inventer, ce serait décider à sa place de ce que la feature doit faire.
- **Le type** : `fix` si l'issue porte le label `bug`, sinon `feature`.

## 2. Situer le dépôt

- `git status --porcelain --untracked-files=all` et `git branch --show-current`.
- **Base** : `develop` s'il existe sur le dépôt distant (`git ls-remote --heads origin develop`), sinon `main`. Puis `git fetch origin <base>`.
- **La branche de l'issue existe déjà** (`feature/<n>-…` ou `fix/<n>-…`, en local ou sur `origin`) : la reprendre. Le travail a peut-être commencé : lire `git log origin/<base>..` et le diff avant de planifier la suite.
- **Du travail non commité sur une autre branche** : s'arrêter et le dire. Changer de branche emporterait ces modifications dans la nouvelle feature, et les mélangerait. C'est à l'utilisateur de les envoyer, de les mettre de côté ou de les abandonner.
- Sinon, **`git-ops` crée la branche** et déplace la carte :

```
/feature de l'issue #<n>.
1. Crée la branche <type>/<n>-<slug> depuis origin/<base> : git switch --no-track -c <type>/<n>-<slug> origin/<base>
2. Carte de l'issue en « En cours » : pwsh -NoProfile -File .harness/tools/board.ps1 -Issue <n> -Status 'En cours'
Ne pousse rien. Si une étape échoue ou si un hook la refuse, arrête-toi et rapporte le message exact.
```

  Le `<slug>` reprend le titre en quelques mots anglais, en minuscules, séparés par des tirets (`feature/42-invoice-pdf-export`). `--no-track` évite que la branche suive `<base>` : un `git push` sans argument pousserait sinon sur la base. En **mode essai**, le brief s'arrête à l'étape 1.

## 3. Proposer un plan court

En quelques lignes : les fichiers créés ou modifiés, les tests prévus (un par critère au moins), l'approche si elle n'est pas évidente, et une estimation de la taille. S'appuyer sur `AGENTS.md`, `ARCHITECTURE.md` et le code existant (codegraph d'abord, ou `explorer` pour une exploration large).

- **Faire valider le plan** avant que `dev` commence : une mauvaise direction coûte une implémentation entière. Deux exceptions. Si l'issue est triviale (un fichier, une approche évidente), annoncer le plan et continuer. Si l'utilisateur a dit de ne pas attendre, continuer aussi.
- **Au-delà d'environ 400 lignes**, hors fichiers générés, proposer de découper l'issue (une PR = une issue, moins de 400 lignes). Ne pas découper soi-même.
- **Un besoin d'architecture** (nouvelle dépendance majeure, nouveau motif, besoin d'infra) se signale : il demande un ADR, voire l'agent `architect`, avant le code.

## 4. Faire implémenter par `dev`

Appeler le subagent `dev`, **sans paramètre `model`** (le hook `model-guard` le refuse). Brief :

```
Implémente l'issue #<n> sur la branche <branche> : <titre>.
Critères d'acceptation, à remplir tous : <liste>.
Plan validé : <plan>.
Le code et ses tests, selon AGENTS.md, ARCHITECTURE.md et les conventions des modules.
Lance scripts/test.ps1 (et scripts/build.ps1 s'il existe) jusqu'au vert.
Ne commite pas. Rends : les fichiers modifiés, le résultat des tests, et chaque critère rempli ou non.
```

Vérifier ensuite par soi-même : `git status`, les tests relancés, chaque critère confronté au code. Un critère non rempli repart chez `dev`.

## 5. Relire et nettoyer

- **`/review`** sur le travail de la branche. Ses points « À corriger » repartent chez `dev`, avec le `chemin:ligne`. Puis un nouveau `/review`. **Deux tours au plus** : au-delà, le problème demande souvent une décision plutôt qu'une correction, et il se signale dans le compte rendu. Les points « À voir » sont signalés, sans être corrigés d'office.
- **`/lint`**. S'il reste des avertissements, les signaler.
- Les skills `/review` et `/lint` absents du projet : faire la même chose à la main, avec `reviewer` puis `linter`, et le dire.

## 6. Rendre compte et proposer `/ship`

```
**/feature #<n>** : <branche> (<créée | reprise>), carte <« En cours » | inchangée (essai)>

Fait : <fichiers, +a/−b lignes>
Tests : <commande, résultat>
Critères :
- [x] <critère rempli>
- [ ] <critère non rempli : pourquoi>
/review : <n tours, ce qui a été corrigé, ce qui reste « À voir »>
/lint : <vert | ce qui reste>
```

Puis proposer **`/ship`**, sans le lancer : il pousse et ouvre la PR, et c'est à l'utilisateur de dire quand. En mode essai, écrire dans le fichier demandé les gestes GitHub qui auraient été faits (la carte en « En cours ») et ce compte rendu.
