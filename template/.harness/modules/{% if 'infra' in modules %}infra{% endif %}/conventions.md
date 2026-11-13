# Conventions infra

Module `infra` du harness, pour le dépôt d'infrastructure (type `infra`). S'ajoute aux conventions communes (`.harness/agents/conventions.md`).

**Fusionner dans `main`, c'est déployer.** ArgoCD applique ce qui est sur `main`, et OpenTofu et Ansible décrivent l'état voulu des machines et des services. Un changement d'infra passe par une PR et une revue `auditor`, et c'est l'utilisateur qui fusionne.

## Organisation

```
ansible/                    playbooks, rôles, inventaire, requirements.yml
tofu/<périmètre>/           un dossier par périmètre (DNS, hyperviseur, VPN…), chacun son état
clusters/<cluster>/
├── bootstrap/              ce qui installe ArgoCD et l'Application racine
├── platform/               les briques communes du cluster
└── apps/<app>/             la configuration de chaque app
charts/                     les charts maison
secrets/                    les *.sops.yaml, seulement chiffrés
.sops.yaml                  les règles de chiffrement
hosts/<hôte>/*.md           les notes d'une machine : installation, réception, inventaire
docs/                       la doc
```

## Agir sur l'infra

- **Aucune action qui modifie l'infra sans l'accord explicite de l'utilisateur**, donné dans la conversation pour cette action-là. Un accord ne vaut pas pour la suivante. Est une action toute commande qui change l'état d'une machine, d'un cluster ou d'un service, par exemple :
  - OpenTofu : `apply`, `destroy`, `import`, `state rm`, `state mv`, `taint` ;
  - Ansible : `ansible-playbook` sans `--check`, et les commandes ad hoc (`ansible <hôtes> -m …`) ;
  - `kubectl` : `apply`, `create`, `delete`, `replace`, `patch`, `edit`, `scale`, `rollout restart`, `drain`, `cordon`, `label`, `annotate` ;
  - `helm` : `install`, `upgrade`, `rollback`, `uninstall` ;
  - `argocd` : `app sync`, `app delete`.

  Cette liste donne des exemples : dans le doute, c'est une action.
- **La lecture est libre, sauf celle des secrets** : `tofu plan`, `ansible-playbook --check --diff`, `kubectl get`, `describe`, `logs` et `diff`, `argocd app diff`. On lit avant d'agir, et on montre ce que l'action va changer. Les secrets ne se lisent pas, même pour dépanner (section *Secrets*).
- **Le cluster est toujours nommé** : `kubectl --context <cluster>`, jamais le contexte courant par défaut. Une commande sans contexte peut viser le mauvais cluster.
- **Git décrit l'état durable.** Un `kubectl apply` à la main sert à dépanner, et il est suivi d'un commit qui rend le même état à Git, sinon ArgoCD le défait.

## OpenTofu

- **Plan enregistré, puis apply de ce plan** : `tofu plan -out=<périmètre>.tfplan`, relu, puis `tofu apply <périmètre>.tfplan`. Jamais d'`apply` sans plan, ni d'`-auto-approve` sur un plan que l'utilisateur n'a pas vu.
- **Versions figées** : `required_version` et `required_providers` avec une version exacte, et `.terraform.lock.hcl` commité.
- **L'état et les plans ne vont jamais dans Git** (le bloc `.gitignore` du harness ignore `*.tfstate`, `*.tfplan` et `.terraform/`), et un agent ne lit jamais un `*.tfstate`, un `*.tfplan` ni un `*.tfvars` : ils contiennent des secrets en clair. Les valeurs sensibles arrivent par l'environnement (`sops exec-env`).
- `tofu fmt` avant chaque commit.

## Ansible

- **Ansible tourne dans WSL Ubuntu** : il n'est pas pris en charge nativement sous Windows. On le lance par `wsl ansible-playbook …`, depuis la racine du dépôt.
- **Les rôles sont idempotents** : un deuxième passage ne change rien. `--check --diff` avant chaque vrai passage.
- **Une tâche qui manipule un secret porte `no_log: true` et `diff: false`** : sans cela, `--diff` affiche le fichier rendu avec ses valeurs.
- **Collections et rôles figés** dans `ansible/requirements.yml`.
- L'inventaire est versionné, sans secret. Les secrets viennent de SOPS (`community.sops`).

## Kubernetes et GitOps

- **Manifestes déclaratifs** sous `clusters/<cluster>/`. Les images et les charts ont une version figée, jamais `latest`.
- Une app se déploie par sa configuration dans `clusters/<cluster>/apps/<app>/` et le chart commun, pas par des manifestes écrits à la main.

## Secrets : SOPS + age

- **Seuls les `*.sops.yaml` chiffrés entrent dans Git**, sous `secrets/`.
- **Un fichier de secrets est chiffré en entier**, sauf les manifestes `Secret` de Kubernetes. Pour eux seuls, une `creation_rule` de `.sops.yaml`, posée sur leur chemin, limite le chiffrement aux champs `data` et `stringData`, pour que leur structure reste lisible dans les diffs. Les secrets d'OpenTofu et d'Ansible ont leurs clés à plat : une règle `data`/`stringData` les laisserait en clair, avec pourtant un bloc `sops:` qui les fait paraître chiffrés.
- **La clé age ne vit jamais dans le dépôt**, et un agent ne la lit jamais.
- Un agent ne déchiffre pas un secret pour l'afficher : pas de `sops -d` dont la sortie arrive dans la conversation, pas de `kubectl get secret` avec une sortie `-o yaml`, `json`, `jsonpath` ou `go-template` (les valeurs n'y sont qu'en base64), pas de `kubectl edit secret`, pas de `kubectl config view --raw`, pas de lecture d'un kubeconfig. L'utilisateur modifie un secret lui-même, par `sops edit`.
- Un nouveau secret se chiffre avant son premier commit (`sops -e -i`). Un secret commité en clair est compromis : on le change, puis on le chiffre.
