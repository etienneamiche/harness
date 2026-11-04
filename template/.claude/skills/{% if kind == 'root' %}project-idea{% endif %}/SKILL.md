---
name: project-idea
description: Tient les idées de nouveaux projets du dépôt project-ideas (IDEAS.md et ideas/) — note une idée en une phrase par scripts/idea.ps1, crée sa page après quelques questions, change son statut (retenue, en pause, abandonnée), et fait commiter et pousser par git-ops. À utiliser pour toute idée de nouvelle app, d'outil, de jeu ou de projet à garder pour plus tard, même dite en passant, et pour consulter ou faire mûrir ces idées : « /project-idea un carnet de recettes partagé », « j'ai une idée d'app », « note cette idée de projet », « crée la page de l'idée 7 », « abandonne l'idée 3 », « mets l'idée 5 en pause », « quelles idées de projet j'ai ? ». Pas pour une fonctionnalité du projet courant (/idea), préciser une issue (/spec), ni démarrer un projet (/start-project).
argument-hint: "[\"une phrase\" | page <n> | <statut> <n> [raison]]"
---

# /project-idea

Les idées de **nouveaux projets** vivent dans le dépôt privé `project-ideas`, cloné à la racine. `IDEAS.md` est la liste centrale, avec une ligne par idée. `ideas/<nnnn>-<slug>.md` est la page d'une idée qui mûrit. Le mode d'emploi, les statuts et le format du tableau sont dans `project-ideas/README.md` et `project-ideas/ARCHITECTURE.md` : les lire au premier usage.

Une fonctionnalité du projet courant n'est pas une idée de projet. Elle relève de `/idea`, qui ouvre une issue : le dire.

**Règles du dépôt**
- **Une idée s'ajoute par `scripts/idea.ps1`**, jamais en écrivant à la main dans le tableau. Le script récupère les modifications distantes, numérote et refuse les doublons. Le skill lance toujours le script avec `-NoCommit`.
- **Le commit et le push passent par `git-ops`**, directement sur `main` : `project-ideas` n'a ni PR ni issue pour ses idées. Le commit est **limité aux fichiers du skill** (`-- IDEAS.md`, plus la page s'il y en a une), pour ne pas emporter autre chose de l'index.
- Une ligne écrite depuis l'interface web de GitHub se lit telle quelle : ne pas reformater le tableau.
- **Une idée ne se supprime jamais** : son statut change. `lancée` appartient à `/start-project`, et `décrite` à la création de la page.

**Mode essai** : si l'utilisateur demande un essai ou « sans publier », le skill écrit ses fichiers comme d'habitude, mais n'appelle pas `git-ops`. Il dit ce qui aurait été commité, avec le message, et laisse les modifications dans `project-ideas/`, à garder ou à annuler.

## 1. Préparer le dépôt

- `project-ideas/` absent : le dire, renvoyer à `pwsh -NoProfile -File scripts/pull-all.ps1`, puis s'arrêter. Ne pas lancer le script soi-même.
- Lire l'état : `git -C project-ideas status -sb`. Le dépôt doit être sur `main`, et `IDEAS.md` sans modification locale. Sinon, le dire et s'arrêter : une modification en cours appartient à l'utilisateur.
- Pour une page ou un statut, récupérer d'abord les modifications distantes : `git -C project-ideas pull --ff-only`. Pour une nouvelle idée, `idea.ps1` le fait lui-même.

## 2. Noter une idée

L'idée arrive en une phrase (`/project-idea "…"`), ou au fil de la conversation (« j'ai une idée d'app pour… », « note cette idée de projet »).

1. **La phrase** : une ligne courte, qui dit ce qu'on construirait (« Carnet de recettes partagé avec la famille »). Une idée donnée en plusieurs phrases se résume en une. Les détails ne sont pas perdus : les citer dans le compte rendu, pour la future page. Si la demande ne dit pas clairement quelle idée noter, demander la phrase.
2. **Les idées proches** : lire `IDEAS.md`. Une idée qui dit la même chose avec d'autres mots se signale, avec son numéro et son statut, et on demande s'il faut quand même noter la nouvelle. Le script ne repère que les doublons exacts.
3. **L'ajout** : `pwsh -NoProfile -File project-ideas/scripts/idea.ps1 "<phrase>" -NoCommit`. La phrase est entre guillemets doubles : une apostrophe y est courante. Un `$`, un backtick ou un guillemet double dans la phrase se reformule sans eux. Une commande Git écrite en clair aussi (« git push », « git reset ») : `git-guard` refuserait la commande entière. Si le script refuse (doublon, `IDEAS.md` modifié, branche autre que `main`, pull impossible), rapporter son message tel quel et s'arrêter.
4. **Le commit** : par `git-ops` (section 5), avec le message `docs(ideas): add idea <n>, <phrase>`.

Une idée notée par l'utilisateur lui-même, avec sa phrase, se commite sans validation supplémentaire : la commande était la demande. Une idée tirée de la conversation se montre d'abord (« je note : n° … « <phrase> » ? »).

## 3. Créer la page d'une idée

`/project-idea page <n>`, ou « développe l'idée 7 », « crée sa page ».

1. **Trouver la ligne** n° `<n>` dans `IDEAS.md`. Si elle n'existe pas, le dire. Si l'idée a déjà une page, proposer de la compléter plutôt que d'en créer une autre. Une idée `lancée` ou `abandonnée` : demander confirmation avant de la décrire.
2. **Compléter ce qui manque** pour remplir `project-ideas/_template.md` : le problème, l'idée, pour qui, ce qu'elle ferait (3 à 5 points), l'archi pressentie. Poser **seulement les questions qui manquent**, toutes dans un seul message, numérotées, puis **attendre la réponse**. Ce que l'utilisateur ne sait pas encore va dans « Questions ouvertes » : c'est le rôle de cette section. Une demande qui donne déjà tout ne déclenche aucune question.
3. **Rédiger la page** d'après `_template.md` :
   - le fichier : `ideas/<nnnn>-<slug>.md`, avec le numéro sur 4 chiffres et un slug court en kebab-case, sans accent ;
   - le titre : `# <n> — <titre court>` ;
   - la ligne de rappel : la date est celle de la colonne « Ajoutée ».
   
   L'archi reste une intuition : `/start-project` y reviendra.
4. **La faire valider**. Montrer la page, appliquer les corrections, puis l'écrire.
5. **Mettre à jour la ligne** de `IDEAS.md`, par une modification ciblée de cette seule ligne :
   - le statut devient `` `décrite` `` s'il était `` `brute` `` ; un autre statut (`retenue`, `en pause`…) ne change pas ;
   - la colonne « Page » reçoit `[page](ideas/<nnnn>-<slug>.md)` ;
   - les autres cellules et les autres lignes ne changent pas.
6. **Le commit** : par `git-ops`, avec le message `docs(ideas): describe idea <n>, <titre court>`. Il contient les deux fichiers.

## 4. Changer un statut

« Retiens l'idée 4 », « mets la 5 en pause », « abandonne la 3, ça existe déjà ».

| Statut | Quand | Ce qui change |
|---|---|---|
| `retenue` | Prête pour `/start-project` | Le statut. Proposer `/start-project <n>` |
| `en pause` | Mise de côté | Le statut |
| `abandonnée` | On n'y croit plus | Le statut, et la raison |
| `brute`, `décrite` | — | Pas à la main : `décrite` vient de la page |
| `lancée` | — | Réservé à `/start-project`, qui ajoute le lien vers le dépôt : refuser et le dire |

- **La raison d'un abandon est demandée** si elle n'est pas donnée. Elle va dans la section « Notes » de la page, avec la date du jour. Si l'idée n'a pas de page, elle va à la fin de la cellule « Idée » : ` — abandonnée : <raison>`.
- **Pour `retenue`**, une idée sans page est signalée : `/start-project` part de la page. Proposer de la créer d'abord.
- Modifier seulement la cellule « Statut » de la ligne, plus la raison s'il y en a une.
- **Le commit** : par `git-ops`, avec le message `docs(ideas): mark idea <n> as <statut>`. Il contient `IDEAS.md`, plus la page si la raison y est écrite.

## 5. Faire commiter et pousser par `git-ops`

Appeler le subagent `git-ops`, sans paramètre `model` :

```
/project-idea : commite et pousse sur main dans project-ideas.
1. git -C project-ideas add -- <fichiers>
2. git -C project-ideas commit -m "<message>" -- <fichiers>
3. git -C project-ideas push
Rends le hash du commit. Si une étape échoue ou si un hook la refuse, arrête-toi et rapporte le message exact.
```

- `<fichiers>` : `IDEAS.md`, plus la page s'il y en a une, chacun nommé. Le chemin en fin de commit le limite à ces fichiers.
- **Message entre guillemets doubles**, avec les mêmes précautions que la phrase : pas de `$`, de backtick ni de guillemet double dedans.
- **Push refusé** (une idée notée ailleurs entre-temps) :
  - pour une nouvelle idée, faire annuler le commit par `git-ops` (`git -C project-ideas reset --soft HEAD~1`, puis `git -C project-ideas restore --staged --worktree -- IDEAS.md`), puis recommencer une fois la section 2 à partir du script, qui refait le pull et renumérote ;
  - pour une page ou un statut, faire récupérer les modifications par `git-ops` (`git -C project-ideas pull --rebase`), puis repousser (`git -C project-ideas push`). Sur un conflit, `git-ops` s'arrête, et le skill le rapporte sans le résoudre seul.
- **Mode essai** : pas d'appel à `git-ops`.

## 6. Rendre compte

```
**/project-idea** : idée n° <n> « <phrase> » — <brute | <statut>, page ideas/… | statut <statut>>, commit <hash> poussé
```

Ajouter, s'il y en a : les idées proches, les détails gardés pour la page, et la suite naturelle. Pour une idée `brute`, c'est `/project-idea page <n>`. Pour une idée `décrite`, c'est la retenir. Pour une idée `retenue`, c'est `/start-project <n>`.

**Sans argument**, ou à la question « quelles idées j'ai ? » : lire `IDEAS.md` et résumer. Donner le nombre d'idées par statut, puis les idées `retenue` et `décrite`, avec leur numéro. Ne rien modifier.
