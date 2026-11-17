# Quiz App - Projet d'évaluation Conteneurisation

## Mission

Vous intégrez une équipe DevOps chargée de **conteneuriser, sécuriser et déployer** l'application **Quiz App** sur Microsoft Azure, puis d'automatiser ses livraisons.

Le **code applicatif est fourni**. Votre mission concerne la conteneurisation, l'exploitation, la sécurité et le déploiement ; **ne modifiez pas la logique métier**. Une modification ciblée d'une question de quiz présente dans le code servira à démontrer le processus de livraison.

L'application comporte un frontend, un backend et une base PostgreSQL. Elle peut utiliser un service d'envoi d'emails ; les fonctionnalités qui en dépendent doivent être configurées uniquement si les accès nécessaires sont fournis.

## Résultat attendu

1. Faire fonctionner Quiz App localement avec Docker, Docker Compose et PostgreSQL persistant.
2. Construire des images sécurisées, analyser les vulnérabilités et documenter les corrections.
3. Déployer les images via Azure Container Registry (ACR) sur Azure Container Apps avec Azure CLI.
4. Connecter le backend à un PostgreSQL externe (Neon recommandé, ou solution compatible).
5. Mettre en place une CI/CD avec **GitHub Actions (recommandé)** ou **GitLab CI/CD (autorisé)** : contrôles sur Pull/Merge Request, scan Trivy bloquant, puis publication et déploiement après fusion dans `main`.
6. Présenter le travail et les preuves de chaque jalon lors d'une soutenance.

Les jalons sont validés progressivement. Une difficulté sur PostgreSQL cloud n'annule pas les jalons déjà acquis et n'interdit pas de démontrer la partie CI/CD technique.

## Travail à partir du dépôt officiel

Le formateur publie le code de départ et les consignes sur la branche `main` de son dépôt **de référence**. **Chaque groupe crée un fork de ce dépôt sur GitHub**, puis travaille exclusivement dans son fork. Les branches `feature/*` et les Pull Requests doivent cibler **`main` du fork du groupe**, jamais `main` du formateur.

- Sur GitHub : faites un fork **par groupe**, activez GitHub Actions si nécessaire et configurez vos propres secrets et autorisations Azure. Les secrets du dépôt d’origine ne sont pas transmis au fork.
- Sur GitLab (alternative admise) : créez un projet de groupe à partir du code de départ et utilisez des **Merge Requests dirigées vers `main` de votre projet**, pas vers le dépôt officiel.
- Aucun accès en écriture au dépôt du formateur n’est nécessaire. Transmettez au formateur l’URL de votre dépôt de groupe.

## Commencer

Lisez les documents dans cet ordre :

- [Présentation du projet](docs/01-presentation-projet.md)
- [Consignes techniques](docs/02-consignes-techniques.md)
- [Jalons et validations](docs/03-jalons-validation.md)
- [Exigences CI/CD](docs/04-pipeline-cicd.md)
- [Fonctionnalités avancées](docs/05-bonus-azure.md)
- [Soutenance et livrables](docs/06-soutenance-livrables.md)
- [Ressources officielles](docs/07-ressources.md)
- [Documentation technique de Quiz App : ports, API et configuration](docs/08-documentation-technique.md)
- [Utilisation responsable de l’IA](docs/09-utilisation-ia.md)

**Important :** les comptes Azure for Students peuvent être limités par les crédits, quotas, régions et autorisations. Vérifiez les possibilités de votre abonnement avant de créer des ressources payantes. Supprimez les ressources inutilisées après sauvegarde des preuves et accord du formateur.

## Règles générales

- Travail en groupe ; déposez le lien de votre dépôt et les preuves demandées au formateur.
- Versionnez les fichiers de configuration, les scripts et les workflows **que vous produisez**.
- Ne commitez jamais de mots de passe, URL PostgreSQL contenant des identifiants, clés API, secrets GitHub/GitLab ou fichiers `.env` réels.
- Une démonstration validée reste acquise même si les ressources cloud sont supprimées ensuite.

## Réalisation du groupe : guide d'exploitation

Schémas et analyse : [architecture/README.md](architecture/README.md). Preuves datées par jalon : [preuves/](preuves/) (J0 à J6).

### Prérequis

- Docker (avec Docker Compose), Git, et un compte GitHub (fork de ce dépôt).
- Azure CLI 2.90 ou plus, un abonnement **Azure for Students** actif (`az login`). La stratégie de l'abonnement n'autorise que certaines régions : voir `preuves/J0`.
- Un compte **Neon** (PostgreSQL managé) pour la base cloud.
- Trivy, en local ou via Docker : `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.76.1 ...`

### 1. Lancement local (Docker Compose)

```bash
cp .env.example .env          # puis remplacer les valeurs (jamais versionné)
docker compose up -d --build  # frontend (Nginx) + backend + PostgreSQL
curl http://localhost:8087/health
```

L'application est sur http://localhost:8087. Les données PostgreSQL sont dans le volume `pgdata` : elles survivent à `docker compose down` / `up`. Seul `docker compose down -v` les efface.

### 2. Sécurité des images (Trivy)

```bash
trivy image --scanners vuln --severity HIGH,CRITICAL quiz-frontend:local
trivy image --scanners vuln --severity CRITICAL --exit-code 1 quiz-backend:local   # contrôle bloquant
```

Les rapports avant/après et les vulnérabilités résiduelles sont dans `preuves/J2/rapport-trivy.md`.

### 3. Déploiement cloud (Azure Container Apps et Neon)

```bash
cp .env.azure.example .env.azure        # secrets cloud (jamais versionné)
./scripts/set-database-url.sh           # chaîne Neon copiée -> .env.azure (sslmode=verify-full)
./scripts/check-db.sh                   # test TLS avec le pilote du backend
./scripts/init-db.sh                    # schéma via database/init.sql (une fois)
./scripts/deploy.sh                     # ACR + images (tag = commit) + environnement + 2 Container Apps
```

`deploy.sh` est relançable : il met à jour ce qui existe (nouvelle révision). Il crée l'environnement en mode **WorkloadProfiles** et choisit une région disponible parmi `ACA_LOCATIONS` (voir `preuves/J4`). Les secrets vont dans les **secrets** des Container Apps, jamais dans les images.

### 4. CI/CD (GitHub Actions)

```bash
./scripts/setup-github-oidc.sh    # identité Azure fédérée (OIDC), affiche les 3 identifiants
```

1. Déclarer `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` et `AZURE_SUBSCRIPTION_ID` dans *Settings > Secrets and variables > Actions*.
2. Protéger `main` : PR obligatoire, contrôle requis **`Build et Trivy`**, pas de contournement.
3. Démonstration : modifier une question (`questions_*.js`) sur une branche `feature/*`, puis ouvrir une PR. La CI construit les images et lance Trivy. Après la fusion, la CD publie dans l'ACR et crée de nouvelles révisions. Voir `preuves/J6/cicd.md`.

### 5. Nettoyage (maîtrise des coûts)

```bash
./scripts/destroy.sh   # supprime le groupe rg-quiz-app : ACR, environnement, apps, identités, logs
```

L'ACR (SKU Basic) est facturé à la journée : on le supprime dès que les jalons sont validés et les preuves conservées. La base Neon (offre gratuite) se supprime dans la console Neon si besoin.

## Usage de l'IA

- **Outil :** Claude Code, un assistant IA d'Anthropic intégré à VS Code.
- **Tâches assistées :** analyse du code fourni (ports, variables, dépendance à la base), rédaction et relecture des Dockerfiles, du `docker-compose.yml` et des scripts Azure CLI (`scripts/`), diagnostic des incidents (environnement Container Apps « Express », capacité saturée en France Central, option `channel_binding` ignorée par le pilote `pg`), rédaction des rapports de `preuves/`.
- **Vérification des propositions :**
  - lancement réel en local (Compose, persistance du volume) ;
  - analyses Trivy avant et après les corrections ;
  - tests « à blanc » des scripts avec des commandes Azure simulées ;
  - lecture de la documentation officielle Microsoft et Neon ;
  - tests HTTP sur Azure (`/health`, API, isolement du backend) et lecture des journaux.

  Les sorties de ces tests sont conservées dans `preuves/`.
- **Secrets :** aucun secret n'est versionné, et les valeurs de `.env` et `.env.azure` ne sont pas transmises à l'assistant. **Exception, signalée :** une chaîne de connexion Neon a été collée une fois par erreur dans la conversation. Le projet Neon concerné a été supprimé aussitôt, ce qui a rendu le mot de passe inutilisable (voir `preuves/J5`). Ensuite, l'assistant a été **autorisé explicitement** à utiliser la CLI Neon (compte connecté par navigateur) pour recréer le projet. La nouvelle chaîne a été transmise directement de la CLI au fichier `.env.azure` (`neon connection-string ... | scripts/set-database-url.sh`), sans jamais être affichée.
