#!/usr/bin/env bash
# =============================================================
# J6 — Identité Azure utilisée par GitHub Actions pour le déploiement (CD),
#      SANS mot de passe ni clé : fédération d'identité OIDC.
#
# Principe : à chaque exécution, GitHub fournit un jeton signé qui indique
# le dépôt et la branche. Azure l'échange contre un accès temporaire
# UNIQUEMENT s'il correspond au "sujet" autorisé ci-dessous (branche main).
# Une Pull Request (ou un fork) ne peut donc pas obtenir cet accès.
#
# Droits accordés (moindre privilège) :
#   - AcrPush + Reader sur l'ACR uniquement       -> publier les images
#   - Container Apps Contributor sur le groupe    -> nouvelles révisions
#   - Managed Identity Operator sur l'identité qui tire les images
#     (les apps l'utilisent ; la mise à jour doit pouvoir la conserver)
# Aucun accès aux secrets de la base (la CD ne fait que changer l'image).
#
# Idempotent. Prérequis : az login, ACR et Container Apps créés (deploy.sh).
# =============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

GITHUB_REPO="${GITHUB_REPO:-faresfettah/eval-quiz-app}"
GH_IDENTITY="${GH_IDENTITY:-id-quiz-github}"
SUBJECT="repo:${GITHUB_REPO}:ref:refs/heads/main"

# ---------- 1. Identité managée ----------
if ! az identity show --name "$GH_IDENTITY" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo ">> Création de l'identité '$GH_IDENTITY'"
  az identity create --name "$GH_IDENTITY" --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" --output none
fi
CLIENT_ID="$(az identity show --name "$GH_IDENTITY" --resource-group "$RESOURCE_GROUP" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show --name "$GH_IDENTITY" --resource-group "$RESOURCE_GROUP" --query principalId -o tsv)"

# ---------- 2. Confiance envers GitHub (OIDC), branche main uniquement ----------
# Incident J6 : GitHub peut présenter le sujet dans un format "immuable" qui
# contient les numéros du compte et du dépôt :
#   repo:<compte>@<id-compte>/<dépôt>@<id-dépôt>:ref:refs/heads/main
# Le sujet doit correspondre EXACTEMENT, sinon Azure refuse (AADSTS700213).
# On déclare donc les deux formats (toujours la seule branche main).
add_federation() {   # $1 = nom de la fédération, $2 = sujet
  if ! az identity federated-credential show --name "$1" --identity-name "$GH_IDENTITY" \
       --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
    echo ">> Fédération OIDC : $2"
    az identity federated-credential create --name "$1" --identity-name "$GH_IDENTITY" \
      --resource-group "$RESOURCE_GROUP" \
      --issuer "https://token.actions.githubusercontent.com" \
      --subject "$2" --audiences "api://AzureADTokenExchange" --output none
  fi
}
add_federation github-main "$SUBJECT"

# Numéros du compte et du dépôt (API publique de GitHub, ou variables
# GITHUB_OWNER_ID / GITHUB_REPO_ID si l'API est indisponible)
if [ -z "${GITHUB_OWNER_ID:-}" ] || [ -z "${GITHUB_REPO_ID:-}" ]; then
  IDS="$(curl -fsS "https://api.github.com/repos/$GITHUB_REPO" \
    | python3 -I -c "import sys, json; d = json.load(sys.stdin, strict=False); print(d['owner']['id'], d['id'])")"
  GITHUB_OWNER_ID="${IDS% *}"
  GITHUB_REPO_ID="${IDS#* }"
fi
add_federation github-main-ids \
  "repo:${GITHUB_REPO%%/*}@${GITHUB_OWNER_ID}/${GITHUB_REPO#*/}@${GITHUB_REPO_ID}:ref:refs/heads/main"

# ---------- 3. Rôles (portée la plus étroite possible) ----------
assign_role() {   # $1 = rôle, $2 = portée
  local n
  n="$(az role assignment list --scope "$2" \
    --query "length([?principalId=='$PRINCIPAL_ID' && roleDefinitionName=='$1'])" -o tsv)"
  if [ "$n" = "0" ]; then
    echo ">> Rôle '$1' sur ${2##*/}"
    az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
      --assignee-principal-type ServicePrincipal --role "$1" --scope "$2" --output none
  fi
}
ACR_ID="$(az acr show --name "$ACR_NAME" --query id -o tsv)"
RG_ID="$(az group show --name "$RESOURCE_GROUP" --query id -o tsv)"
PULL_IDENTITY_ID="$(az identity show --name "$IDENTITY" --resource-group "$RESOURCE_GROUP" --query id -o tsv)"
assign_role "AcrPush" "$ACR_ID"
assign_role "Reader" "$ACR_ID"
assign_role "Container Apps Contributor" "$RG_ID"
assign_role "Managed Identity Operator" "$PULL_IDENTITY_ID"

# ---------- 4. Valeurs à déclarer dans GitHub ----------
# Ce sont des IDENTIFIANTS, pas des secrets (aucun mot de passe n'existe).
# On les range quand même dans les "secrets" GitHub pour ne pas les exposer.
cat <<EOF

>> À déclarer dans GitHub : Settings > Secrets and variables > Actions > New repository secret
   AZURE_CLIENT_ID       = $CLIENT_ID
   AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)
   AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)
EOF
