import db from "./db.js";

const stmtGet = db.prepare("SELECT * FROM users WHERE user_id = ?");
const stmtGetByEmail = db.prepare("SELECT * FROM users WHERE email = ?");
const stmtGetAll = db.prepare("SELECT * FROM users");
const stmtUpdatePassword = db.prepare("UPDATE users SET password = ?, updated_at = ? WHERE user_id = ?");

const stmtUpsert = db.prepare(`
  INSERT INTO users (
    user_id, username, call_name, email, password,
    contact_name, contact_phone, contact_name2, contact_phone2,
    last_checkin_date, last_alert_at, language, updated_at
  ) VALUES (
    @user_id, @username, @call_name, @email, @password,
    @contact_name, @contact_phone, @contact_name2, @contact_phone2,
    @last_checkin_date, @last_alert_at, @language, @updated_at
  )
  ON CONFLICT(user_id) DO UPDATE SET
    username          = @username,
    call_name         = @call_name,
    email             = @email,
    password          = @password,
    contact_name      = @contact_name,
    contact_phone     = @contact_phone,
    contact_name2     = @contact_name2,
    contact_phone2    = @contact_phone2,
    last_checkin_date  = @last_checkin_date,
    last_alert_at     = @last_alert_at,
    language          = @language,
    updated_at        = @updated_at
`);

/**
 * Retrieve a user row and return it as the same shape the old JSON store used,
 * so the rest of the code does not need to change its expectations.
 */
export function getUser(userId) {
  const row = stmtGet.get(userId);
  if (!row) return null;
  return rowToUser(row);
}

/**
 * Insert or update a user.  Accepts the same object shape returned by getUser().
 */
export function upsertUser(user) {
  stmtUpsert.run({
    user_id: user.userId,
    username: user.username ?? null,
    call_name: user.callName ?? null,
    email: user.email ?? null,
    password: user.password ?? null,
    contact_name: user.emergencyContact?.name ?? null,
    contact_phone: user.emergencyContact?.phone ?? null,
    contact_name2: user.emergencyContact2?.name ?? null,
    contact_phone2: user.emergencyContact2?.phone ?? null,
    last_checkin_date: user.lastCheckinDate ?? null,
    last_alert_at: user.lastAlertAt ?? null,
    language: user.language ?? 'en',
    updated_at: user.updatedAt ?? new Date().toISOString(),
  });
}

/**
 * Look up a user by email address.
 */
export function getUserByEmail(email) {
  const row = stmtGetByEmail.get(email);
  if (!row) return null;
  return rowToUser(row);
}

/**
 * Update a user's password hash.
 */
export function updatePassword(userId, hashedPassword) {
  stmtUpdatePassword.run(hashedPassword, new Date().toISOString(), userId);
}

/**
 * Retrieve all users (for the scheduler's daily scan).
 */
export function getAllUsers() {
  const rows = stmtGetAll.all();
  return rows.map(rowToUser);
}

/* ── helpers ─────────────────────────────────────────────── */

function rowToUser(row) {
  return {
    userId: row.user_id,
    username: row.username,
    callName: row.call_name,
    email: row.email,
    password: row.password,
    emergencyContact: {
      name: row.contact_name,
      phone: row.contact_phone,
    },
    emergencyContact2: {
      name: row.contact_name2,
      phone: row.contact_phone2,
    },
    lastCheckinDate: row.last_checkin_date,
    lastAlertAt: row.last_alert_at,
    language: row.language ?? 'en',
    updatedAt: row.updated_at,
  };
}
