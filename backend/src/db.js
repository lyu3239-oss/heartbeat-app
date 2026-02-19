import dotenv from "dotenv";
import { Pool } from "pg";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, "../.env") });

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error("DATABASE_URL is required for PostgreSQL connection");
}

const sslEnabled = String(process.env.PGSSL || "false").toLowerCase() === "true";

const pool = new Pool({
  connectionString,
  ssl: sslEnabled ? { rejectUnauthorized: false } : false,
});

let initialized = false;

export async function initDb() {
  if (initialized) return;

  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      user_id           TEXT PRIMARY KEY,
      username          TEXT,
      call_name         TEXT,
      email             TEXT UNIQUE,
      password          TEXT,
      contact_name      TEXT,
      contact_phone     TEXT,
      contact_name2     TEXT,
      contact_phone2    TEXT,
      last_checkin_date TEXT,
      last_alert_at     TEXT,
      language          TEXT DEFAULT 'en',
      updated_at        TEXT
    )
  `);

  initialized = true;
}

export default pool;
