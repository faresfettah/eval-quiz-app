#!/usr/bin/env bash
# =============================================================
# J3 — Construit les images, les tague avec le commit Git
#      et les publie dans l'Azure Container Registry.
#
# Prérequis : Docker démarré, "az login" fait, ACR créé (acr-setup.sh).
# Tag       : SHA court du commit (ex. d5cf53f), calculé dans config.sh.
#             On sait exactement quel code est dans l'image. Suffixe "-dirty"
#             si des fichiers suivis par Git sont modifiés sans commit.
#             La CI pourra imposer son propre tag : TAG=<sha> ./scripts/push-images.sh
# =============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

case "$TAG" in
  *-dirty) echo "!! Modifications non commitées : l'image sera taguée '$TAG'" ;;
esac

REGISTRY="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
echo ">> Registre : $REGISTRY  |  tag : $TAG"

# Connexion de Docker à l'ACR avec le compte Azure (jeton temporaire,
# aucun mot de passe stocké dans le script).
az acr login --name "$ACR_NAME"

# --platform linux/amd64 : architecture attendue par Azure Container Apps
# (indispensable si l'image est construite sur un Mac Apple Silicon).
docker build --platform linux/amd64 -t "$REGISTRY/$BACKEND_IMAGE:$TAG" ./backend
docker build --platform linux/amd64 -t "$REGISTRY/$FRONTEND_IMAGE:$TAG" .

docker push "$REGISTRY/$BACKEND_IMAGE:$TAG"
docker push "$REGISTRY/$FRONTEND_IMAGE:$TAG"

echo ">> Images présentes dans l'ACR :"
for repo in "$BACKEND_IMAGE" "$FRONTEND_IMAGE"; do
  az acr manifest list-metadata --registry "$ACR_NAME" --name "$repo" \
    --query "[].{image:'$repo', tags:join(', ', tags || \`[]\`), digest:digest, date:createdTime}" \
    --output table
done
