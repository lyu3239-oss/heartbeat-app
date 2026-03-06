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

  // Main users table
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
      language          TEXT DEFAULT 'en',
      updated_at        TEXT,
      created_at        TIMESTAMPTZ DEFAULT NOW(),
      apple_user_id     TEXT UNIQUE
    )
  `);

  // Add columns if they don't exist (safe migration for existing DBs)
  await pool.query(`
    DO $$ BEGIN
      ALTER TABLE users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
      ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_user_id TEXT;
      ALTER TABLE users DROP COLUMN IF EXISTS last_alert_at;
    EXCEPTION WHEN OTHERS THEN NULL;
    END $$;
  `);

  // Create unique index on apple_user_id if not exists
  await pool.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_users_apple_user_id
    ON users (apple_user_id) WHERE apple_user_id IS NOT NULL
  `);

  // Refresh tokens table
  await pool.query(`
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id          SERIAL PRIMARY KEY,
      user_id     TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
      token_hash  TEXT NOT NULL,
      expires_at  TIMESTAMPTZ NOT NULL,
      created_at  TIMESTAMPTZ DEFAULT NOW()
    )
  `);

  // Verification codes table (replaces in-memory Map)
  await pool.query(`
    CREATE TABLE IF NOT EXISTS verification_codes (
      id          SERIAL PRIMARY KEY,
      email       TEXT NOT NULL,
      code        TEXT NOT NULL,
      expires_at  TIMESTAMPTZ NOT NULL,
      created_at  TIMESTAMPTZ DEFAULT NOW()
    )
  `);

  // Indexes for performance
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash ON refresh_tokens(token_hash)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_verification_codes_email ON verification_codes(email)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_verification_codes_expires_at ON verification_codes(expires_at)`);
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)`);

  // Clean up expired tokens and codes on startup
  await pool.query(`DELETE FROM refresh_tokens WHERE expires_at < NOW()`);
  await pool.query(`DELETE FROM verification_codes WHERE expires_at < NOW()`);

  initialized = true;
}

export default pool;
