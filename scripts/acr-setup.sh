#!/usr/bin/env bash
# =============================================================
# J3 — Crée le groupe de ressources et l'Azure Container Registry.
# Idempotent : si les ressources existent déjà, rien n'est recréé.
#
# Prérequis : Azure CLI, "az login" fait, abonnement Azure for Students
#             sélectionné (az account show).
# Coût      : l'ACR Basic est facturé à la journée (environ 0,17 $/jour,
#             sur le crédit étudiant). Nettoyage : ./scripts/destroy.sh
# =============================================================
set -euo pipefail                  # arrêt à la première erreur
cd "$(dirname "$0")/.."            # exécution depuis la racine du dépôt
source scripts/config.sh

echo ">> Abonnement : $(az account show --query name -o tsv)"

echo ">> Groupe de ressources '$RESOURCE_GROUP' ($LOCATION)"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" \
  --tags projet=quiz-app --output none

if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo ">> ACR '$ACR_NAME' déjà présent : rien à créer"
else
  # Le nom doit être libre dans tout Azure
  if [ "$(az acr check-name --name "$ACR_NAME" --query nameAvailable -o tsv)" != "true" ]; then
    echo "!! Le nom '$ACR_NAME' est déjà pris. Choisissez-en un autre : ACR_NAME=monnom $0" >&2
    exit 1
  fi
  echo ">> Création de l'ACR '$ACR_NAME' (SKU $ACR_SKU)"
  # --admin-enabled false : pas de compte administrateur (login/mot de passe
  # partagé). Les accès passeront par des identités Azure avec des rôles
  # limités (AcrPull pour Container Apps, AcrPush pour la CI).
  az acr create --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --sku "$ACR_SKU" --admin-enabled false --output none
fi

az acr show --name "$ACR_NAME" \
  --query "{nom:name, serveur:loginServer, sku:sku.name, region:location, compteAdmin:adminUserEnabled}" \
  --output table
