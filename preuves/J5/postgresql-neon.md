# J5 — PostgreSQL cloud (Neon)

**Date :** 17/11/2026
**Scripts :**

| Script | Rôle |
|---|---|
| `scripts/set-database-url.sh` | Enregistre la chaîne Neon dans `.env.azure` (non versionné), sans l'afficher |
| `scripts/check-db.sh` (+ `check-db.cjs`) | Teste la connexion chiffrée avec le pilote `pg` du backend |
| `scripts/init-db.sh` | Crée le schéma avec le script **existant** `database/init.sql` (idempotent) |
| `scripts/deploy.sh` | Pousse la chaîne dans le secret `database-url` du backend |

Aucune chaîne de connexion ni aucun mot de passe ne figure dans ce document.

## 1. Choix de la base

| Élément | Valeur | Justification |
|---|---|---|
| Fournisseur | Neon (PostgreSQL managé, offre gratuite) | Recommandé par la consigne. PostgreSQL reste dans Docker Compose en local |
| Projet | `quiz-app`, PostgreSQL **17** | Même version majeure que le PostgreSQL local (`postgres:17.12`) |
| Région | **AWS eu-central-1 (Francfort)** | Même ville que le backend (Azure Germany West Central) : faible latence, données en Europe |
| Point d'accès | **pooled** (hôte `-pooler`) | Le pool `pg` du backend ouvre jusqu'à 20 connexions par réplica. Le pooler de Neon (PgBouncer) les mutualise |

## 2. Connexion chiffrée (TLS)

La chaîne utilise `sslmode=verify-full` : la connexion est **chiffrée** et le **certificat du serveur est vérifié** (autorité de confiance + nom d'hôte). Résultat de `./scripts/check-db.sh`, avec le pilote `pg 8.23.1` du backend :

```text
{
  connexion_ms: 304,
  chiffrement_tls: 'TLSv1.3',
  certificat_verifie: true,
  certificat_serveur: '*.c-7.eu-central-1.aws.neon.tech',
  base: 'neondb',
  utilisateur: 'neondb_owner',
  version_postgres: '17.12',
  nb_tables: 0
}
```

**Exigences TLS du pilote, vérifiées dans le code de `pg-connection-string 2.14.1` :**
- `sslmode=verify-full` active le TLS avec `rejectUnauthorized`, donc un certificat invalide ferait échouer la connexion.
- `sslmode=require`, la valeur que Neon propose par défaut, est traité **comme `verify-full`**, mais avec un avertissement `SECURITY WARNING` dans les journaux. On écrit donc directement `verify-full`.
- `channel_binding=require`, ajouté par Neon, est une option **libpq** (`psql`). Le pilote `pg` l'ignore : il ne l'active que via l'option de code `enableChannelBinding`, qu'on ne touche pas, car la consigne interdit le développement métier. La sécurité de la connexion repose donc sur TLS `verify-full` et l'authentification SCRAM-SHA-256.
- Côté `psql` (script d'initialisation), `sslrootcert=system` vérifie le certificat avec les autorités du système. libpq **refuse** même cette option avec un mode plus faible que `verify-full`.

## 3. Initialisation du schéma

Les tables ne se créent pas toutes seules : `./scripts/init-db.sh` exécute une fois `database/init.sql`, avec le client officiel `psql` lancé dans un conteneur.

```text
>> Création du schéma avec database/init.sql
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE INDEX
 Schema |     Name     | Type  |    Owner
--------+--------------+-------+--------------
 public | answers      | table | neondb_owner
 public | quiz_results | table | neondb_owner
 public | users        | table | neondb_owner
```

`init.sql` ne contient pas de `IF NOT EXISTS`. Le script vérifie donc d'abord si la table `users` existe : relancé, il affiche « Schéma déjà présent : init.sql n'est pas rejoué » au lieu d'échouer sur « already exists ».

## 4. Secret côté Azure

- La chaîne est stockée dans le **secret** `database-url` de la Container App backend. La variable d'environnement `DATABASE_URL` n'en contient qu'une référence (`secretref:database-url`).
- Elle vient du fichier local `.env.azure` (droits `600`, ignoré par Git) et n'apparaît ni dans l'image, ni dans les scripts, ni dans le dépôt, ni dans les journaux.
- Le pipeline CI/CD (J6) ne fera que changer l'image (`az containerapp update --image`) : il n'a **jamais besoin de connaître la chaîne Neon**. C'est le principe du moindre privilège.
- Le déploiement crée une **nouvelle révision** (`ca-quiz-backend--v261117161447`), qui lit les secrets à jour.

## 5. Démonstration : enregistrement et persistance

Test réalisé à travers l'URL publique du frontend (`https://ca-quiz-frontend.happysand-8f33d265.germanywestcentral.azurecontainerapps.io`), avec les mêmes requêtes que le navigateur et un utilisateur de démonstration (adresse `@example.com`, réservée aux tests) :

| Heure (UTC) | Action | Résultat |
|---|---|---|
| 15:17:40 | `POST /api/users` (inscription) | **201** `{"id":1,"firstname":"Demo J5",...}` |
| 15:17:40 | `POST /api/results` (score 2/3, 3 réponses) | **201** `{"quizResultId":1}` |
| 15:17:42 | Envoi de l'email | Échec journalisé (`Failed to send email`, clé Resend factice). L'erreur est capturée : le résultat est déjà enregistré |
| 15:17:49 | Lecture **directe dans Neon** (`psql`, TLS) | 1 utilisateur, 1 résultat, **3 réponses** |
| 15:17:53 | `az containerapp revision restart` (backend) | Nouveau réplica, processus Node.js relancé (`Server running on port 3007` à 15:18:09) |
| 15:19:02 | Relecture **à travers l'application** (`GET /api/admin/results`) | **200** : `Demo J5`, 1 tentative, meilleur score 2/3, toujours présent ✅ |

```text
 id | firstname | score | total_questions |        completed_at        | nb_reponses
----+-----------+-------+-----------------+----------------------------+-------------
  1 | Demo J5   |     2 |               3 | 2026-11-17 15:17:40.378978 |           3
```

**Pourquoi les données persistent :** elles sont stockées dans Neon, **en dehors** des conteneurs. Redémarrer, recréer ou même supprimer les Container Apps (`destroy.sh`) ne les efface pas. En local, c'est le volume `pgdata` qui joue ce rôle (J1).

## 6. Points de vigilance documentés

- **Mise en veille de Neon (offre gratuite) :** la base s'endort après quelques minutes sans activité. Le premier accès la réveille, et la connexion mesurée a pris 304 ms. Or le backend abandonne une connexion au bout de **2 s** (`connectionTimeoutMillis: 2000` dans `server.js`). Un réveil plus lent pourrait donc faire échouer la première requête (HTTP 500), alors que la suivante passerait. Avant une démonstration, on « réveille » la base avec `./scripts/check-db.sh`.
- **Message trompeur :** l'API répond « Results saved and email sent » même quand l'envoi échoue, car le message est écrit en dur dans le code. Les journaux montrent l'échec réel. On ne modifie pas ce comportement, puisque le développement métier est hors périmètre.
- **Incident de sécurité :** pendant la mise en place, une chaîne de connexion complète (mot de passe compris) a été collée par erreur dans une conversation avec l'assistant IA. Il s'agissait d'un premier projet, créé aux **États-Unis** (us-east-2) par défaut. Ce projet vide a été **supprimé**, ce qui a rendu le mot de passe exposé inutilisable, puis recréé à Francfort avec de nouveaux identifiants. Depuis, la chaîne passe directement de la CLI Neon à `.env.azure` (`neon connection-string ... | ./scripts/set-database-url.sh`), sans être affichée.

## 7. Commandes

```bash
./scripts/set-database-url.sh   # chaîne copiée depuis Neon (presse-papiers) -> .env.azure
./scripts/check-db.sh           # TLS 1.3, certificat vérifié
./scripts/init-db.sh            # schéma (une seule fois, idempotent)
./scripts/deploy.sh             # secret database-url + nouvelle révision
```
