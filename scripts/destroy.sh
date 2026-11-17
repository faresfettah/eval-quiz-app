#!/usr/bin/env bash
# =============================================================
# Nettoyage : supprime le groupe de ressources du projet, donc TOUT son contenu :
#   ACR (et les images), environnement et Container Apps, identité managée,
#   espace Log Analytics.
# ⚠️ Opération IRRÉVERSIBLE. Conserver les preuves (sans secrets) AVANT.
# La base Neon (externe à Azure) n'est pas touchée.
#
# Usage : ./scripts/destroy.sh          (demande une confirmation)
#         ./scripts/destroy.sh --yes    (sans confirmation, ex. en CI)
# =============================================================
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh

if [ "$(az group exists --name "$RESOURCE_GROUP")" != "true" ]; then
  echo ">> Le groupe '$RESOURCE_GROUP' n'existe pas : rien à supprimer"
  exit 0
fi

echo ">> Ressources qui vont être supprimées :"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{nom:name, type:type}" --output table

if [ "${1:-}" != "--yes" ]; then
  read -r -p "Tapez le nom du groupe ($RESOURCE_GROUP) pour confirmer : " ANSWER
  if [ "$ANSWER" != "$RESOURCE_GROUP" ]; then
    echo ">> Annulé"
    exit 1
  fi
fi

# --no-wait : la suppression continue côté Azure (quelques minutes)
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
echo ">> Suppression lancée. Vérification : az group exists --name $RESOURCE_GROUP  (doit afficher false)"
