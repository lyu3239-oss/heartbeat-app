import Database from "better-sqlite3";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Data directory is one level up from src, in 'data' folder
const dataDir = path.resolve(__dirname, "..", "data");

if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, "heartbeat.db");
const db = new Database(dbPath);

// Enable WAL mode for better concurrent read performance.
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS users (
    user_id           TEXT PRIMARY KEY,
    username          TEXT,
    call_name         TEXT,
    email             TEXT,
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

// Migration: add language column if missing (existing DBs)
try { db.exec("ALTER TABLE users ADD COLUMN language TEXT DEFAULT 'en'"); } catch (_) { }
// Migration: add call_name column if missing (existing DBs)
try { db.exec("ALTER TABLE users ADD COLUMN call_name TEXT"); } catch (_) { }

export default db;
