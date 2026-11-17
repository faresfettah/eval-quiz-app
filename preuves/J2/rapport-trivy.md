# J2 — Rapport de sécurité Trivy

- **Date :** 17/11/2026
- **Outil :** Trivy 0.76.1, exécuté dans un conteneur (`aquasec/trivy:0.76.1`), scanner `vuln`
- **Images analysées :** `quiz-frontend` et `quiz-backend`

| Fichier | Contenu |
|---|---|
| `01-initial-frontend.txt`, `01-initial-backend.txt` | Rapports **avant** correction (images du J1) |
| `02-final-frontend.txt`, `02-final-backend.txt` | Rapports **après** correction |

## 1. Synthèse

| Image | État | CRITICAL | HIGH | MEDIUM | LOW |
|---|---|---|---|---|---|
| frontend | initial | **1** | 12 | 4 | 44 |
| frontend | **final** | 0 | 0 | 0 | 0 |
| backend (système Alpine) | initial | 0 | 0 | 1 | 0 |
| backend (système Alpine) | **final** | 0 | 0 | 0 | 0 |
| backend (paquets npm) | initial | 0 | 6 | 14 | 1 |
| backend (paquets npm) | **final** | 0 | 0 | 2 | 0 |

Selon la politique CI (échec sur toute vulnérabilité CRITICAL), l'image frontend initiale aurait été **bloquée**. Les deux images finales passent le contrôle.

## 2. Vulnérabilités pertinentes et corrections

### Frontend (Nginx `nginx-unprivileged:1.31.7-alpine3.24`)

| Paquet | CVE | Sévérité | Cause | Correction |
|---|---|---|---|---|
| brotli-libs 1.2.0-r1 | CVE-2026-111497 | CRITICAL | Paquet Alpine obsolète dans l'image de base | `apk upgrade` → 1.2.1-r0, ou suppression avec libcurl |
| curl / libcurl 8.22.0-r0 | CVE-2026-92392 (+ autres) | HIGH | curl est présent dans l'image, mais Nginx n'en a pas besoin | `apk del curl` : outil supprimé |
| libexpat 2.9.0-r0 | CVE-2026-113351 | HIGH | Paquet Alpine obsolète | `apk upgrade` → 2.10.0-r0 |
| musl 1.2.6-r2 | CVE-2026-107891 | HIGH | Paquet Alpine obsolète | `apk upgrade` → 1.2.6-r3 |

Ajout dans le `Dockerfile` (étape `production`) :

```dockerfile
USER root
RUN apk upgrade --no-cache && apk del --no-cache curl
# ... puis retour à l'utilisateur non-root
USER 101
```

On repasse en root uniquement pendant la construction. Le conteneur, lui, tourne toujours en utilisateur `nginx` (uid 101).

### Backend (Node `node:24.22.3-alpine3.24`)

| Paquet | CVE | Sévérité | Emplacement | Correction |
|---|---|---|---|---|
| undici, brace-expansion, ip-address, glob, minimatch, postcss-selector-parser | dont CVE-2026-109383 (undici, HIGH) et CVE-2026-102276 (brace-expansion, HIGH) | 6 HIGH, 12 MEDIUM, 1 LOW | `/usr/local/lib/node_modules/npm/` : l'outil **npm livré avec l'image**, et non l'application | Suppression de npm, npx, corepack et yarn après `npm ci` |
| zlib 1.3.2-r1 | CVE-2026-4738 | MEDIUM | Paquet Alpine | `apk upgrade` → 1.4-r0 |

**Justification :** le conteneur démarre avec `node server.js`. npm et yarn ne servent qu'à installer les dépendances pendant le build. Les laisser dans l'image n'apporte rien à l'exécution et ajoute des failles. On les **supprime** plutôt que de les mettre à jour.

## 3. Vulnérabilités résiduelles (acceptées et documentées)

| Paquet | CVE | Sévérité | Chaîne de dépendance |
|---|---|---|---|
| glob 10.5.0 | CVE-2026-118773 | MEDIUM | `resend` → `@react-email/render` → `pretty` → `js-beautify` → `glob` |
| minimatch 9.0.9 | CVE-2026-118764 | MEDIUM | … → `js-beautify` → `glob` / `editorconfig` → `minimatch` |

**Pourquoi elles restent :**

1. Il s'agit de dépendances **indirectes** de la bibliothèque d'emails `resend`, et non de dépendances choisies par le projet.
2. La correction demande des versions **majeures** (glob 14, minimatch 11) incompatibles avec ce que déclare `js-beautify` (`glob ^10`). Forcer ces versions (`overrides`) risquerait de casser le module d'emails.
3. **Risque d'exploitation faible :** ce sont des dénis de service déclenchés par un motif de fichiers (glob) malveillant. Le backend n'utilise ni `js-beautify` ni le rendu React des emails (il envoie du HTML directement), et aucune donnée utilisateur n'est transmise à `glob` ou `minimatch`.
4. Sévérité MEDIUM : ces vulnérabilités ne bloquent pas la politique CI, qui échoue uniquement sur CRITICAL.

**Piste ultérieure :** mettre à jour `resend` vers une version majeure plus récente qui ne dépend plus de `@react-email/render`. C'est une évolution de dépendance applicative, à tester séparément.

## 4. Vérification fonctionnelle après correction

- `docker compose up -d` : backend `healthy`, frontend démarré
- `GET /health` → `{"status":"ok"}` ; `/` → 200 ; `/gestion-quiz` → 200
- Les conteneurs tournent en non-root : backend `uid=1000(node)`, frontend `uid=101(nginx)`
- `npm`, `yarn` et `curl` sont absents des images finales
- Les données du J1 sont toujours présentes : le volume `pgdata` n'a pas été touché

## 5. Commandes utilisées

```bash
alias trivy='docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache aquasec/trivy:0.76.1'

# Avant correction
docker tag quiz-backend:local quiz-backend:initial
docker tag quiz-frontend:local quiz-frontend:initial
trivy image --scanners vuln quiz-backend:initial  > preuves/J2/01-initial-backend.txt
trivy image --scanners vuln quiz-frontend:initial > preuves/J2/01-initial-frontend.txt

# Après correction
docker compose build
trivy image --scanners vuln quiz-backend:local  > preuves/J2/02-final-backend.txt
trivy image --scanners vuln quiz-frontend:local > preuves/J2/02-final-frontend.txt

# Contrôle équivalent à la CI (code retour 1 si CRITICAL)
trivy image --scanners vuln --severity CRITICAL --exit-code 1 quiz-frontend:local
```
