#!/usr/bin/env bash
# =============================================================
# J5 — Crée le schéma (tables) sur la base cloud avec le script EXISTANT
# database/init.sql. Les tables n'apparaissent pas toutes seules.
#
# Idempotent : si la table "users" existe déjà, init.sql n'est PAS rejoué
# (il ne contient pas de "IF NOT EXISTS" et échouerait : "already exists").
# La chaîne vient de .env.azure (non versionné) et n'est jamais affichée.
#
# Prérequis : Docker (client psql officiel lancé dans un conteneur)
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

# psql dans un conteneur. sslrootcert=system : le certificat de Neon est
# vérifié avec les autorités de certification du système (verify-full).
# ON_ERROR_STOP=1 : arrêt à la première erreur SQL.
psql_cloud() {
  docker run --rm -i -e DATABASE_URL postgres:17.12-alpine3.24 \
    sh -c 'psql "${DATABASE_URL}&sslrootcert=system" -v ON_ERROR_STOP=1 "$@"' psql "$@"
}

if [ "$(psql_cloud -tAc "select to_regclass('public.users') is not null")" = "t" ]; then
  echo ">> Schéma déjà présent (table users trouvée) : init.sql n'est pas rejoué"
else
  echo ">> Création du schéma avec database/init.sql"
  psql_cloud < database/init.sql
fi

echo ">> Tables de la base cloud :"
psql_cloud -c "\dt"
