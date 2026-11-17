# =============================================================
# Backend Quiz App : API Node.js / Express
# =============================================================

# Tag précis (Node 24 LTS, Alpine 3.24) : image légère et reproductible.
FROM node:24.22.3-alpine3.24

WORKDIR /app

# Mode production : certaines bibliothèques (Express) s'optimisent.
ENV NODE_ENV=production

# Dépendances d'abord (cache), installées exactement selon le lockfile,
# sans les dépendances de développement.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Sécurité (J2 - Trivy) :
# 1. Mise à jour des paquets Alpine (corrige zlib CVE-2026-4738).
# 2. Suppression des gestionnaires de paquets livrés avec l'image Node
#    (npm, npx, corepack, yarn) : inutiles à l'exécution ("node server.js"),
#    ils portaient 6 vulnérabilités HIGH (undici, brace-expansion, ip-address...).
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
           /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-* \
           /root/.npm

# Code de l'application (un seul fichier).
COPY server.js ./

# Utilisateur non-root "node" (fourni par l'image officielle).
USER node

EXPOSE 3007

# Lancement direct de node (pas de "npm start") : node reçoit
# directement les signaux d'arrêt envoyés par Docker.
CMD ["node", "server.js"]
