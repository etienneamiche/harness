# Conventions Python

Module `python` du harness. S'ajoute aux conventions communes (`.harness/agents/conventions.md`).

**Python sert aux petits modules** : un traitement long derrière un petit front (téléchargement, conversion…), ou un service interne appelé par une API .NET. **Ce n'est pas la stack des grosses API métier** : un module qui a besoin d'une vraie base de données, de couches ou de beaucoup d'endpoints devient un backend .NET (ou fait l'objet d'un ADR).

## Socle

- **Python 3.14**, version figée dans `backend/.python-version`. **uv** pour l'environnement, les dépendances et le verrouillage (`pyproject.toml`, `uv.lock`). Jamais `pip install` à la main.
- **FastAPI** : la spécification OpenAPI est produite automatiquement. Le front (Orval) ou l'API .NET (Refitter) appellent le module par un **client généré**.
- **`marblestudio-hosting`** (une ligne dans `main.py`) : logs JSON, `/healthz` et `/ready`, Problem Details, identifiant de corrélation, authentification et `current_user` quand le module est exposé.

## Deux usages

| Usage | Appelé par | Exposition | Authentification |
|---|---|---|---|
| Module derrière un front | le front React de l'app, sur `/api` | `lan`, `vpn` ou `public` | celle de l'app (`none`, `forward-auth`, `oidc`) |
| Service interne | une autre app du cluster | **`internal`** : aucune route, NetworkPolicy limitée à l'app appelante | aucune : l'appelant a déjà vérifié l'utilisateur |

**Un dépôt n'a qu'un seul backend.** Un service Python appelé par une API .NET est son propre dépôt (une app en exposition `internal`).

## Organisation : à plat

```
backend/
├── pyproject.toml · uv.lock · .python-version
├── src/<app>/
│   ├── main.py        création de l'app FastAPI + briques communes
│   ├── routes.py      les endpoints (dossier routes/ si le fichier dépasse ~300 lignes)
│   ├── jobs.py        les traitements longs (option jobs)
│   ├── models.py      modèles Pydantic : requêtes, réponses, état des tâches
│   ├── clients/       une API appelée = un module
│   └── config.py      configuration (pydantic-settings)
└── tests/
```

Pas de couches service / dal : les routes appellent directement les fonctions du module. Si le module grossit au point d'en avoir besoin, c'est le signal qu'il doit devenir un backend .NET.

## Traitements longs (option `jobs`)

- **`POST /api/jobs`** valide la demande, enregistre la tâche et répond **202** avec son identifiant. Jamais de requête HTTP qui attend la fin d'un traitement long.
- **`GET /api/jobs/{id}`** : état (`pending`, `running`, `succeeded`, `failed`), progression, erreur éventuelle. **`GET /api/jobs/{id}/events`** : la progression en direct par **SSE**. `GET /api/jobs/{id}/result` : le fichier produit, s'il y en a un.
- **Exécution dans le processus**, par une file asyncio à concurrence réglable (`JOBS__CONCURRENCY`). Pas de Redis ni de Celery ; si le besoin dépasse ça, ADR.
- **L'état des tâches vit dans SQLite**, sur le volume de l'app. Au démarrage, une tâche restée `running` passe `failed` (« interrompue par un redémarrage »), et peut être relancée.
- **Les fichiers produits vont sur le volume persistant**, dans un dossier par tâche, jamais dans l'image ni dans `/tmp`.
- Un traitement long se découpe en étapes qui **publient leur progression** et **vérifient l'annulation** entre deux étapes.

## Données

- **Pas de Postgres.** L'état des tâches et les petites données du module tiennent dans SQLite (bibliothèque standard `sqlite3`, ou `aiosqlite` en asynchrone). Une vraie base de données = un backend .NET.

## Modèles et immuabilité

- **Pydantic v2**, modèles **immuables** (`model_config = ConfigDict(frozen=True)`). Une modification = une copie : `job.model_copy(update={"status": JobStatus.RUNNING})`.
- On ne modifie jamais un objet reçu en paramètre.
- Types partout : paramètres, retours, attributs.

## Clients d'API

- **httpx** asynchrone, un module par API dans `clients/`, un `AsyncClient` partagé (créé au démarrage, fermé à l'arrêt).
- **stamina** pour les nouvelles tentatives, et un délai maximal sur chaque appel.
- Cache en mémoire avec durée de vie quand c'est utile.
- Pour **tes propres API** : client généré depuis leur OpenAPI (openapi-python-client).
- Les réponses externes sont converties en modèles internes dès la frontière.

## Configuration

- **pydantic-settings**, validé au démarrage : une config invalide arrête le module immédiatement.
- Variables d'environnement uniquement (préfixe par section : `JOBS__CONCURRENCY`). Aucun secret dans un fichier.

## Qualité

- **ruff** pour le lint et le format, **pyright** en mode `standard`. Les deux tournent à chaque fin de tour d'agent.
- Leur configuration vit dans **`backend/ruff.toml`** et **`backend/pyrightconfig.json`**, pas dans `pyproject.toml` : ces deux fichiers sont protégés, un agent ne les modifie pas.
- `print()` interdit : le logger de `marblestudio-hosting`.

## Tests

- **pytest** + **pytest-asyncio**, et le client de test de FastAPI (httpx) pour les endpoints.
- Les traitements longs se testent sur de petites entrées, avec les appels externes simulés (`unittest.mock`, ou un faux transport httpx). Jamais un vrai téléchargement dans un test.
