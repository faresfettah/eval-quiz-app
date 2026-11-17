#!/usr/bin/env bash
# =============================================================
# Configuration commune aux scripts Azure. AUCUN SECRET ICI.
# Ce fichier est chargé ("source") par les autres scripts.
# Chaque valeur peut être remplacée par une variable d'environnement, ex. :
#   LOCATION=germanywestcentral ./scripts/acr-setup.sh
# =============================================================

# Région : autorisée par la stratégie "Allowed resource deployment regions"
# de l'abonnement Azure for Students (voir preuves/J0).
LOCATION="${LOCATION:-francecentral}"

# Groupe de ressources : contient TOUTES les ressources du projet
# (le supprimer = tout nettoyer, voir destroy.sh).
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-quiz-app}"

# Nom de l'ACR : unique dans tout Azure (il devient <nom>.azurecr.io),
# 5 à 50 caractères, lettres minuscules et chiffres uniquement.
# Par défaut : suffixe calculé à partir de l'abonnement -> toujours le même
# pour cet abonnement, sans révéler son identifiant.
if [ -z "${ACR_NAME:-}" ]; then
  ACR_NAME="acrquiz$(az account show --query id -o tsv | shasum | cut -c1-6)"
fi
ACR_SKU="${ACR_SKU:-Basic}"   # le moins cher, suffisant pour le projet

# Noms des images dans ACR
BACKEND_IMAGE="quiz-backend"
FRONTEND_IMAGE="quiz-frontend"

# Azure Container Apps (J4)
ENVIRONMENT="${ENVIRONMENT:-cae-quiz-app}"
BACKEND_APP="${BACKEND_APP:-ca-quiz-backend}"
FRONTEND_APP="${FRONTEND_APP:-ca-quiz-frontend}"
