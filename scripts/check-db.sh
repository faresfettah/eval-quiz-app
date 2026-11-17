#!/usr/bin/env bash
# =============================================================
# J5 — Teste la connexion CHIFFRÉE à la base cloud (Neon) avec le pilote
# "pg" du backend (image Docker du backend, aucune installation).
# La chaîne vient de .env.azure (non versionné) et n'est jamais affichée.
#
# Prérequis : Docker, image du backend construite (docker compose build backend)
# =============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

set -a; source .env.azure; set +a
if [ -z "${DATABASE_URL:-}" ]; then
  echo "!! DATABASE_URL est vide dans .env.azure" >&2
  exit 1
fi
case "$DATABASE_URL" in
  *sslmode=verify-full*) ;;
  *) echo "!! Mettez sslmode=verify-full dans DATABASE_URL (chiffrement + certificat vérifié)" >&2; exit 1 ;;
esac

IMAGE="${IMAGE:-quiz-backend:local}"
docker run --rm -e DATABASE_URL \
  -v "$PWD/scripts/check-db.cjs:/app/check-db.cjs:ro" \
  "$IMAGE" node check-db.cjs
