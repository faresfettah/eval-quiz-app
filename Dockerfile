# =============================================================
# Frontend Quiz App : build Vite puis service par Nginx
# Build multi-étapes : Node sert uniquement à construire.
# =============================================================

# ---------- Étape 1 : construction ----------
# Tag précis (Node 24 LTS, Alpine 3.24) : build reproductible.
FROM node:24.22.3-alpine3.24 AS build

WORKDIR /app

# Dépendances d'abord : cette couche reste en cache tant que
# package.json / package-lock.json ne changent pas.
COPY package.json package-lock.json ./
RUN npm ci

# Puis le code source (le .dockerignore exclut backend/, .env, .git, etc.)
COPY . .

# Vite intègre les questions (questions_*.js) et génère dist/
RUN npm run build


# ---------- Étape 2 : exécution ----------
# Nginx "unprivileged" : tourne sans root, écoute sur 8080.
FROM nginxinc/nginx-unprivileged:1.31.7-alpine3.24 AS production

# Sécurité (J2 - Trivy) : passage temporaire en root pour :
# 1. mettre à jour les paquets Alpine (corrige brotli-libs CRITICAL,
#    musl et libexpat HIGH) ;
# 2. supprimer curl/libcurl, inutiles à Nginx (surface d'attaque réduite).
USER root
RUN apk upgrade --no-cache && apk del --no-cache curl

# Adresse du backend par défaut (service Compose "backend").
ENV BACKEND_URL=http://backend:3007

# Modèle de configuration : traité au démarrage (substitution de ${BACKEND_URL}).
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Uniquement les fichiers statiques construits.
COPY --from=build /app/dist /usr/share/nginx/html

USER 101
EXPOSE 8080
# Commande de démarrage héritée de l'image Nginx.
