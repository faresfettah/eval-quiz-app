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

# Code de l'application (un seul fichier).
COPY server.js ./

# Utilisateur non-root "node" (fourni par l'image officielle).
USER node

EXPOSE 3007

# Lancement direct de node (pas de "npm start") : node reçoit
# directement les signaux d'arrêt envoyés par Docker.
CMD ["node", "server.js"]
