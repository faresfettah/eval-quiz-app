#!/usr/bin/env bash
# =============================================================
# J4 — Déploie Quiz App sur Azure Container Apps (script réutilisable).
#
#  1. ACR (acr-setup.sh) + images taguées par commit (push-images.sh)
#  2. Identité managée avec le SEUL rôle AcrPull sur l'ACR (pas de mot de passe)
#  3. Environnement Container Apps (Log Analytics créé automatiquement)
#  4. Backend  : ingress INTERNE, port 3007, secrets Azure
#  5. Frontend : ingress EXTERNE, port 8080, BACKEND_URL = adresse interne HTTPS
#
# Relançable : ce qui existe est mis à jour (nouvelle révision), rien n'est
# recréé. Coût : Container Apps en "Consumption", 0 réplica au repos.
#
# Prérequis : Azure CLI + "az login", Docker démarré, fichier .env.azure
#             (copie de .env.azure.example, JAMAIS versionnée).
# Option    : SKIP_BUILD=1 TAG=<tag> ./scripts/deploy.sh
#             -> redéployer une image déjà présente dans l'ACR, sans build.
# Nettoyage : ./scripts/destroy.sh
# =============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

# ---------- Secrets : fichier local non versionné ----------
if [ ! -f .env.azure ]; then
  echo "!! Fichier .env.azure absent. Créez-le : cp .env.azure.example .env.azure" >&2
  exit 1
fi
set -a; source .env.azure; set +a
for v in RESEND_API_KEY ADMIN_PASSWORD JWT_SECRET; do
  if [ -z "${!v:-}" ]; then
    echo "!! $v est vide dans .env.azure" >&2
    exit 1
  fi
done

source scripts/config.sh
echo ">> Abonnement : $(az account show --query name -o tsv)  |  tag des images : $TAG"

# ---------- 1. Registre et images ----------
./scripts/acr-setup.sh
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  echo ">> SKIP_BUILD=1 : utilisation des images existantes '$TAG'"
  for img in "$BACKEND_IMAGE" "$FRONTEND_IMAGE"; do
    az acr repository show --name "$ACR_NAME" --image "$img:$TAG" --output none \
      || { echo "!! Image $img:$TAG absente de l'ACR" >&2; exit 1; }
  done
else
  TAG="$TAG" ./scripts/push-images.sh
fi
REGISTRY="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
ACR_ID="$(az acr show --name "$ACR_NAME" --query id -o tsv)"

# ---------- 2. Identité managée : droit de LIRE les images, rien d'autre ----------
if ! az identity show --name "$IDENTITY" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo ">> Création de l'identité managée '$IDENTITY'"
  az identity create --name "$IDENTITY" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --output none
fi
IDENTITY_ID="$(az identity show --name "$IDENTITY" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
PRINCIPAL_ID="$(az identity show --name "$IDENTITY" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)"

NB_ROLES="$(az role assignment list --scope "$ACR_ID" \
  --query "length([?principalId=='$PRINCIPAL_ID' && roleDefinitionName=='AcrPull'])" -o tsv)"
if [ "$NB_ROLES" = "0" ]; then
  echo ">> Rôle AcrPull (lecture seule des images) accordé à l'identité, sur l'ACR uniquement"
  az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID" --output none
fi

# ---------- 3. Environnement Container Apps ----------
if ! az containerapp env show --name "$ENVIRONMENT" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo ">> Création de l'environnement '$ENVIRONMENT' (plusieurs minutes)"
  az containerapp env create --name "$ENVIRONMENT" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --logs-destination log-analytics --output none
fi

# Suffixe de révision unique : chaque déploiement crée une révision
# identifiable (et prend en compte les secrets mis à jour).
REV_SUFFIX="v$(date +%y%m%d%H%M%S)"

# Fonction : crée l'application si elle n'existe pas, sinon la met à jour.
#   $1 = nom de l'app, $2 = image, $3 = type d'ingress, $4 = port
#   SECRETS[] et ENV_VARS[] : tableaux préparés avant l'appel
deploy_app() {
  local app="$1" image="$2" ingress="$3" port="$4"
  if az containerapp show --name "$app" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
    echo ">> Mise à jour de '$app' (révision $REV_SUFFIX)"
    if [ "${#SECRETS[@]}" -gt 0 ]; then
      az containerapp secret set --name "$app" --resource-group "$RESOURCE_GROUP" \
        --secrets "${SECRETS[@]}" --output none
    fi
    az containerapp update --name "$app" --resource-group "$RESOURCE_GROUP" \
      --image "$image" --set-env-vars "${ENV_VARS[@]}" \
      --revision-suffix "$REV_SUFFIX" --output none
  else
    echo ">> Création de '$app' (ingress $ingress, port $port)"
    local secret_args=()
    if [ "${#SECRETS[@]}" -gt 0 ]; then
      secret_args=(--secrets "${SECRETS[@]}")
    fi
    az containerapp create --name "$app" --resource-group "$RESOURCE_GROUP" \
      --environment "$ENVIRONMENT" --image "$image" \
      --user-assigned "$IDENTITY_ID" --registry-identity "$IDENTITY_ID" --registry-server "$REGISTRY" \
      --ingress "$ingress" --target-port "$port" \
      --cpu 0.25 --memory 0.5Gi --min-replicas 0 --max-replicas 1 \
      ${secret_args[@]+"${secret_args[@]}"} --env-vars "${ENV_VARS[@]}" \
      --revision-suffix "$REV_SUFFIX" --output none
  fi
}

# ---------- 4. Backend : ingress INTERNE (pas joignable depuis internet) ----------
# Les valeurs sensibles sont des SECRETS de l'app ; les variables
# d'environnement n'en contiennent qu'une référence (secretref:).
SECRETS=("resend-api-key=$RESEND_API_KEY" "admin-password=$ADMIN_PASSWORD" "jwt-secret=$JWT_SECRET")
ENV_VARS=(PORT=3007 "ADMIN_USERNAME=${ADMIN_USERNAME:-admin}"
          RESEND_API_KEY=secretref:resend-api-key
          ADMIN_PASSWORD=secretref:admin-password
          JWT_SECRET=secretref:jwt-secret)
if [ -n "${FROM_EMAIL:-}" ]; then
  ENV_VARS+=("FROM_EMAIL=$FROM_EMAIL")
fi
if [ -n "${DATABASE_URL:-}" ]; then
  SECRETS+=("database-url=$DATABASE_URL")
  ENV_VARS+=(DATABASE_URL=secretref:database-url)
else
  echo "!! DATABASE_URL vide : backend déployé SANS base (suffisant pour /health au J4, requis au J5)"
fi
deploy_app "$BACKEND_APP" "$REGISTRY/$BACKEND_IMAGE:$TAG" internal 3007

BACKEND_FQDN="$(az containerapp show --name "$BACKEND_APP" --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv)"

# ---------- 5. Frontend : ingress EXTERNE (URL publique HTTPS) ----------
# Nginx transmet /api et /health au backend par son adresse INTERNE en HTTPS.
SECRETS=()
ENV_VARS=("BACKEND_URL=https://$BACKEND_FQDN")
deploy_app "$FRONTEND_APP" "$REGISTRY/$FRONTEND_IMAGE:$TAG" external 8080

FRONTEND_FQDN="$(az containerapp show --name "$FRONTEND_APP" --resource-group "$RESOURCE_GROUP" \
  --query properties.configuration.ingress.fqdn -o tsv)"

# ---------- 6. Vérification ----------
echo ">> Révisions actives :"
for app in "$BACKEND_APP" "$FRONTEND_APP"; do
  az containerapp revision list --name "$app" --resource-group "$RESOURCE_GROUP" \
    --query "[?properties.active].{revision:name, image:properties.template.containers[0].image, etat:properties.runningState, sante:properties.healthState}" \
    --output table
done

echo ">> Test : https://$FRONTEND_FQDN/health (premier appel lent : démarrage depuis 0 réplica)"
RESULT=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  RESULT="$(curl -s --max-time 30 -w ' -> HTTP %{http_code}' "https://$FRONTEND_FQDN/health" || true)"
  case "$RESULT" in *"HTTP 200") break ;; esac
  sleep 10
done
echo "   $RESULT"
echo ">> Application : https://$FRONTEND_FQDN"
