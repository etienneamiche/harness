---
name: homelab
description: Répond sur l'infra du homelab — matériel, réseau et adressage, nommage, clusters, exposition des apps, sauvegardes et restauration, roadmap H0 à H5, décisions et points ouverts — à partir de homelab/docs/, en citant le fichier, la section et la date, en séparant ce qui est fait de ce qui est prévu et en signalant les docs qui se contredisent. Lecture seule : aucune commande vers l'infra (ssh, ping, kubectl, tofu, ansible). Pour l'état réel, il dit ce qu'affirment les docs et donne la commande à lancer soi-même. À utiliser pour toute question sur le homelab ou son infra : « quelle IP pour la prochaine machine ? », « où en est H1 ? », « le cluster vps tourne ? », « comment on expose une app ? », « qu'est-ce qu'il reste à acheter ? », « comment je restaure l'hyperviseur ? », « pourquoi deux clusters ? ». Pas pour le harness et ses hooks (/help-harness), un doctor en échec (/doctor), ni pour noter une idée de projet (/project-idea).
argument-hint: "[question]"
---

# /homelab

L'infra du homelab est décrite dans `homelab/docs/`, un dépôt privé. `/homelab` y trouve la réponse, la cite, et dit si elle est encore sûre. Une doc d'infra vieillit : une décision datée en remplace une autre, un « prévu » devient « fait » sans que tous les fichiers suivent. La réponse vaut ce que vaut sa source, et le skill la montre toujours.

**Lecture seule, docs seulement.** Le skill ne lance aucune commande vers l'infra : ni `ssh`, ni `ping`, ni `kubectl`, `argocd`, `tofu`, `ansible`, `curl` sur un hôte du homelab. La lecture de l'état réel arrive avec les wrappers du module `infra`. Il ne modifie aucun fichier de `homelab` : une correction de la doc passe par une PR de ce dépôt.

**Confidentialité.** `homelab` est privé, et ce qui en sort ne doit pas fuiter. Le skill peut citer une adresse, un nom d'hôte ou le domaine **dans la session**. Il ne les écrit jamais ailleurs : ni dans un fichier de `services` ou d'un autre dépôt public, ni dans une issue ou une PR de `harness` ou de `services`, ni dans la page d'état. Il ne lit jamais un secret : ni `*.sops.yaml` déchiffré, ni `*.tfstate`, `*.tfvars`, kubeconfig, ni clé.

## 1. Trouver les docs

- Les docs sont dans `homelab/docs/` (le dépôt `homelab` de `repos.yaml`, cloné à la racine). S'il manque, le dire et renvoyer à `pwsh -NoProfile -File scripts/pull-all.ps1`, puis s'arrêter : sans les docs, il n'y a pas de réponse sûre.
- Fraîcheur du clone : `git --no-optional-locks -C homelab status -sb` dit s'il a des modifications locales et s'il suit une branche distante (`## main...origin/main`), sans écrire dans `homelab/.git`. Le retard qu'il donne vaut au dernier `fetch`. Les dates se lisent sans rien modifier, par l'outil PowerShell (`Format-List` garde chaque date, même enchaînée à une autre commande) : `Get-Item -Force homelab/.git/FETCH_HEAD, homelab/.git -ErrorAction SilentlyContinue | Format-List Name, LastWriteTime, CreationTime`.
  - Sans branche suivie (`## main` seul) : le retard est inconnu.
  - Une ligne `FETCH_HEAD` : son `LastWriteTime` est la date du dernier `fetch`.
  - Pas de ligne `FETCH_HEAD`, avec une branche suivie : pas de `fetch` depuis le clone, c'est le cas juste après le premier `pull-all.ps1`. Le retard court depuis la date du clone, le `CreationTime` de la ligne `.git`. Ne pas l'appeler « dernier `fetch` ».
  - Ne jamais affirmer le clone ni la doc à jour : un clone récent dit seulement que le retard est court. Le skill ne lance ni `git fetch` ni `git pull`. Si la question porte sur une décision récente, ou si le dernier `fetch` (ou le clone) est ancien, il propose `scripts/pull-all.ps1` avant de répondre.
- Lister `homelab/docs/`. Le point d'entrée est la roadmap (`03-roadmap.md`), qui renvoie aux autres docs. Ne pas recopier de mémoire le contenu d'un doc : il change.

**Ce qu'on y trouve.** Lister le dossier et lire le titre de chaque doc pour savoir lequel ouvrir. Les docs couvrent en général :
- le profil, les contraintes, le parc matériel et les achats ;
- ce que le homelab doit héberger, et dans quel ordre ;
- les arbitrages d'architecture et leurs raisons ;
- les phases H0 à H5, les décisions datées et les points reportés : `03-roadmap.md`, et la section « Piste homelab » de `docs/ROADMAP.md` à la racine `services` ;
- l'adressage, le DNS et le nommage ;
- l'installation de l'hyperviseur, la plateforme (clusters, déploiement, exposition, certificats) et la restauration après une panne.

**Problèmes connus** : les issues ouvertes de `homelab` (`gh issue list -R <propriétaire>/homelab --state open`), les ⚠️ et les points reportés de la roadmap.

Le propriétaire se lit dans `repos.yaml` (`owner`).

## 2. Répondre avec sa source

Chercher dans les docs (`Select-String` ou l'outil de recherche, sur `homelab/docs/`), puis lire la section entière, pas seulement la ligne trouvée.

Pour chaque fait de la réponse :
- **Citer** le fichier et la section : `03-roadmap.md`, « H1 — … ». Ajouter la date quand la doc en donne une : « Dernière mise à jour », « Décision du … », la date d'un achat ou d'une installation. Sans date dans la doc, la date du dernier commit qui l'a touchée : `git -C homelab log -1 --format=%cs -- docs/<fichier>`.
- **Fait ou prévu.** Une phase H0 à H5 a un état (le tableau « Piste homelab » de `docs/ROADMAP.md` à la racine, et la roadmap elle-même). Une machine ou un service d'une phase à venir est *prévu*, même si sa doc le décrit au présent. Le dire : « prévu en H2, pas encore installé ». Une adresse réservée n'est pas une machine qui tourne.
- **Les décisions datées priment.** Un encadré « Décision du <date> » remplace ce que dit le corps du doc plus ancien. Quand deux docs se contredisent (un choix, un chiffre, un nom), citer les deux avec leur date, dire lequel paraît le plus récent, et ne pas trancher à la place de l'utilisateur. Un renvoi vers un doc qui n'existe pas (« voir le doc N ») se signale aussi.
- **Ne rien inventer.** Une question à laquelle les docs ne répondent pas reçoit « les docs ne le disent pas », avec ce qui s'en approche. Pas de valeur plausible devinée : une adresse ou un port devinés finissent dans une config.

## 3. L'état réel

« Le cluster tourne ? », « l'hyperviseur est à jour ? », « la sauvegarde a marché cette nuit ? » : les docs ne le savent pas. Répondre en trois temps :
1. **Ce que disent les docs** : l'état prévu ou constaté, avec sa source et sa date (« H1 à venir d'après la roadmap du <date> : le cluster n'est pas encore installé »).
2. **Comment le vérifier** : la commande que l'utilisateur lance lui-même, dans son terminal, prise dans les docs quand elles la donnent (runbook, guide d'installation). Le skill ne la lance pas.
3. **Si l'écart se confirme** : la doc est fausse. C'est une issue de `homelab` (section 4), et la correction viendra ensuite par une PR de ce dépôt.

## 4. Où ranger ce qui ressort

- **Un problème du homelab** (une panne, un point ouvert sans suivi, une doc fausse ou contradictoire) : une issue de `homelab`, dépôt privé, où les détails d'infra ont leur place. Chercher un doublon (`gh issue list -R <propriétaire>/homelab --state open --search '<mots-clés>'`), rédiger le brouillon, le faire valider, puis `git-ops` la crée après accord (sans paramètre `model`) : `gh issue create -R <propriétaire>/homelab --title "<titre>" --body-file '<fichier hors du dépôt>' --label infra`.
- **Un manque du harness ou de l'écosystème** (un skill, une règle, un module `infra` attendu) : une issue `harness-update` sur `harness`, ou une issue `/evolve` sur `services`. Ces dépôts sont **publics** : le brouillon ne contient ni adresse, ni nom d'hôte, ni domaine, ni chiffre du parc. Il décrit le besoin en termes génériques (« un hyperviseur », « le cluster de la maison »).
- Rien n'est créé sans accord.

## 5. Répondre

Une réponse courte, dans cet ordre :
- **Réponse** : en une ou deux phrases, en disant si c'est fait ou prévu.
- **Source** : fichier, section, date. Les contradictions et les renvois cassés, s'il y en a.
- **À vérifier** : pour une question d'état réel, la commande à lancer soi-même.
- **Si besoin** : l'issue proposée, avec son brouillon, et la question d'accord.
