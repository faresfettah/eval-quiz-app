// =============================================================
// J5 — Vérifie la connexion à PostgreSQL cloud (Neon) avec le MÊME pilote
// "pg" que le backend. Affiche le protocole TLS et si le certificat du
// serveur a été vérifié. N'affiche JAMAIS la chaîne de connexion.
// Lancé par scripts/check-db.sh (dans l'image du backend).
// =============================================================
const { Client } = require("pg");

(async () => {
  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    connectionTimeoutMillis: 10000,
  });
  const debut = Date.now();
  await client.connect();
  const connexionMs = Date.now() - debut;

  // Socket réseau utilisée par pg : une socket TLS si la connexion est chiffrée
  const socket = client.connection.stream;
  const r = await client.query(
    "select current_database() as base, current_user as utilisateur, " +
      "split_part(version(), ' ', 2) as version_postgres, " +
      "(select count(*)::int from information_schema.tables where table_schema = 'public') as nb_tables"
  );

  console.log({
    connexion_ms: connexionMs,
    chiffrement_tls: typeof socket.getProtocol === "function" ? socket.getProtocol() : "AUCUN",
    certificat_verifie: socket.authorized === true,
    certificat_serveur: typeof socket.getPeerCertificate === "function"
      ? socket.getPeerCertificate().subject?.CN
      : null,
    ...r.rows[0],
  });
  await client.end();
})().catch((e) => {
  console.error("ECHEC de connexion :", e.message);
  process.exit(1);
});
