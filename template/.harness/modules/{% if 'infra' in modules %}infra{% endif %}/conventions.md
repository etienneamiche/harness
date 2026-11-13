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

- **Aucune action qui modifie l'infra sans l'accord explicite de l'utilisateur**, donné dans la conversation pour cette action-là : `tofu apply` et `destroy`, `ansible-playbook` sans `--check`, `kubectl apply`, `delete`, `replace` et `patch`, `argocd app sync` et `delete`. Un accord ne vaut pas pour la suivante.
- **La lecture est libre** : `tofu plan`, `ansible-playbook --check --diff`, `kubectl get`, `describe`, `logs` et `diff`, `argocd app diff`. On lit avant d'agir, et on montre ce que l'action va changer.
- **Le cluster est toujours nommé** : `kubectl --context <cluster>`, jamais le contexte courant par défaut. Une commande sans contexte peut viser le mauvais cluster.
- **Git décrit l'état durable.** Un `kubectl apply` à la main sert à dépanner, et il est suivi d'un commit qui rend le même état à Git, sinon ArgoCD le défait.

## OpenTofu

- **Plan enregistré, puis apply de ce plan** : `tofu plan -out=<fichier>`, relu, puis `tofu apply <fichier>`. Jamais d'`apply` sans plan, ni d'`-auto-approve` sur un plan que l'utilisateur n'a pas vu.
- **Versions figées** : `required_version` et `required_providers` avec une version exacte, et `.terraform.lock.hcl` commité.
- **L'état ne va jamais dans Git**, et un agent ne lit jamais un `*.tfstate`, un `*.tfplan` ni un `*.tfvars` : ils contiennent des secrets en clair. Les valeurs sensibles arrivent par l'environnement (`sops exec-env`).
- `tofu fmt` avant chaque commit.

## Ansible

- **Ansible tourne dans WSL Ubuntu** : il n'est pas pris en charge nativement sous Windows. On le lance par `wsl ansible-playbook …`, depuis la racine du dépôt.
- **Les rôles sont idempotents** : un deuxième passage ne change rien. `--check --diff` avant chaque vrai passage.
- **Collections et rôles figés** dans `ansible/requirements.yml`.
- L'inventaire est versionné, sans secret. Les secrets viennent de SOPS (`community.sops`).

## Kubernetes et GitOps

- **Manifestes déclaratifs** sous `clusters/<cluster>/`. Les images et les charts ont une version figée, jamais `latest`.
- Une app se déploie par sa configuration dans `clusters/<cluster>/apps/<app>/` et le chart commun, pas par des manifestes écrits à la main.

## Secrets : SOPS + age

- **Seuls les `*.sops.yaml` chiffrés entrent dans Git**, sous `secrets/`. `.sops.yaml` ne chiffre que les champs `data` et `stringData` : la structure reste lisible dans les diffs.
- **La clé age ne vit jamais dans le dépôt**, et un agent ne la lit jamais.
- Un agent ne déchiffre pas un secret pour l'afficher : pas de `sops -d` dont la sortie arrive dans la conversation, pas de `kubectl config view --raw`, pas de lecture d'un kubeconfig. L'utilisateur modifie un secret lui-même, par `sops edit`.
- Un nouveau secret se chiffre avant son premier commit (`sops -e -i`). Un secret commité en clair est compromis : on le change, puis on le chiffre.
