# J3 — Azure CLI et Azure Container Registry

**Date :** 17/11/2026

**Scripts :**

| Script | Rôle |
|---|---|
| `scripts/config.sh` | Noms communs aux scripts, sans aucun secret |
| `scripts/acr-setup.sh` | Création du groupe de ressources et de l'ACR (idempotent) |
| `scripts/push-images.sh` | Build, tag par commit Git et publication des images |

## 1. Ressources créées avec Azure CLI

```text
$ ./scripts/acr-setup.sh
Groupe de ressources :
Nom          Region         Etat
rg-quiz-app  francecentral  Succeeded

ACR :
Nom            Serveur                   Sku    Admin
acrquizd78449  acrquizd78449.azurecr.io  Basic  False
```

| Choix | Justification |
|---|---|
| Région `francecentral` | Autorisée par la stratégie de l'abonnement (voir J0) et proche des utilisateurs |
| Groupe `rg-quiz-app` (tag `projet=quiz-app`) | Regroupe toutes les ressources : le supprimer nettoie tout (`destroy.sh`) |
| SKU **Basic** | Le moins cher, suffisant (quelques images, faible trafic) |
| Nom `acrquizd78449` | Doit être unique dans tout Azure. Le suffixe est calculé à partir de l'abonnement (empreinte), sans révéler son identifiant |
| `--admin-enabled false` | Pas d'identifiant ni de mot de passe partagés. Les accès passeront par des identités Azure aux droits limités : `AcrPull` pour Container Apps (J4), `AcrPush` pour la CI (J6) |

## 2. Images publiées, avec des tags identifiables

```text
$ ./scripts/push-images.sh
Image          Tags     Digest
quiz-backend   d5cf53f  sha256:3f8c09e991d7a649647e9034f1bf126af29866a8528a970734daadc12f4800e0
quiz-frontend  d5cf53f  sha256:99a1b198d422155cdcfe01e731b657a4f2d15c6a61c96e701f42d94293398d0e
```

- **Tag = SHA court du commit Git** (`d5cf53f` = fusion de la PR #2 dans `main`). On sait exactement quel code se trouve dans chaque image, et on peut revenir à une version précise. Le tag `latest` n'est pas utilisé, car il ne dit pas quelle version est déployée.
- Si des fichiers suivis par Git sont modifiés sans commit, le script ajoute `-dirty` au tag, pour ne jamais faire passer un code non commité pour un commit.
- Le **digest** (`sha256:...`) est l'empreinte unique et immuable du contenu de l'image.
- Dans l'ACR, chaque dépôt contient aussi deux manifestes **sans tag**. BuildKit publie un *index* (celui qui porte le tag) qui référence l'image `linux/amd64` et une **attestation de provenance** (informations sur la construction). C'est normal.

## 3. Contrôles sur les images publiées

| Contrôle | Résultat |
|---|---|
| Plateforme (`docker image inspect`) | `linux/amd64` pour les deux images, ce qu'attend Azure Container Apps |
| Trivy `--severity HIGH,CRITICAL --exit-code 1` | Code retour `0` pour les deux images : aucune vulnérabilité HIGH ou CRITICAL (corrections du J2 incluses) |

## 4. Sécurité de la publication

- `az acr login` donne à Docker un **jeton temporaire** obtenu avec le compte Azure : aucun mot de passe n'est écrit dans les scripts ni dans le dépôt.
- `--platform linux/amd64` dans le script garantit la bonne architecture, même si l'image est construite sur un Mac Apple Silicon (arm64).

## 5. Commandes de vérification

```bash
az group list --query "[].{nom:name, region:location, etat:properties.provisioningState}" -o table
az acr list --query "[].{nom:name, serveur:loginServer, sku:sku.name, admin:adminUserEnabled}" -o table
az acr repository list --name acrquizd78449 -o table
az acr repository show-tags --name acrquizd78449 --repository quiz-frontend -o table
```
