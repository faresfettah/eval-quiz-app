#!/usr/bin/env bash
# =============================================================
# J5 — Enregistre la chaîne de connexion Neon dans .env.azure (non versionné).
#
# Usage (macOS) : 1. dans Neon, copier la chaîne "pooled" (Cmd + C)
#                 2. ./scripts/set-database-url.sh
# Le script lit le presse-papiers (ou l'entrée standard), remplace
# sslmode=require par sslmode=verify-full, entoure la valeur d'apostrophes
# et remplace la ligne DATABASE_URL. La chaîne n'est JAMAIS affichée.
# =============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f .env.azure ]; then
  echo "!! Fichier .env.azure absent. Créez-le : cp .env.azure.example .env.azure" >&2
  exit 1
fi

if [ -t 0 ]; then
  URL="$(pbpaste)"          # presse-papiers macOS
else
  URL="$(cat)"              # ou entrée standard : ... | ./scripts/set-database-url.sh
fi
URL="$(printf '%s' "$URL" | tr -d '\r\n' | sed 's/sslmode=require/sslmode=verify-full/')"

case "$URL" in
  postgres://*|postgresql://*) ;;
  *) echo "!! Le presse-papiers ne contient pas une chaîne PostgreSQL (postgresql://...). Copiez-la dans Neon puis relancez." >&2; exit 1 ;;
esac
case "$URL" in
  *"'"*) echo "!! La chaîne contient une apostrophe : à saisir à la main dans .env.azure" >&2; exit 1 ;;
esac
case "$URL" in
  *sslmode=verify-full*) ;;
  *) echo "!! sslmode=verify-full absent : ajoutez ?sslmode=verify-full à la chaîne" >&2; exit 1 ;;
esac

# Remplacement de la ligne DATABASE_URL (la valeur passe par l'environnement,
# jamais par la ligne de commande ni l'écran)
TMP="$(mktemp)"
URL="$URL" awk -v q="'" '
  /^DATABASE_URL=/ { print "DATABASE_URL=" q ENVIRON["URL"] q; done = 1; next }
  { print }
  END { if (!done) print "DATABASE_URL=" q ENVIRON["URL"] q }
' .env.azure > "$TMP"
mv "$TMP" .env.azure
chmod 600 .env.azure        # fichier de secrets : lisible par moi seul

echo ">> DATABASE_URL enregistrée dans .env.azure (non versionné)"
case "$URL" in *-pooler.*) echo "   - hôte : pooled (-pooler) ✅" ;; *) echo "   - ⚠️ hôte SANS -pooler : activez 'Connection pooling' dans Neon" ;; esac
echo "   - sslmode=verify-full ✅"
# Région de la base (pas un secret) : à comparer avec celle du backend
REGION="$(printf '%s' "$URL" | sed -nE 's#.*@[^/]*\.([a-z0-9-]+)\.(aws|azure)\.neon\.tech.*#\1 (\2)#p')"
echo "   - région Neon : ${REGION:-inconnue} (backend Azure : Germany West Central = Francfort)"
