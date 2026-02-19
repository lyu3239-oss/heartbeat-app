import db from "./db.js";

/**
 * Retrieve a user row and return it as the same shape the old JSON store used,
 * so the rest of the code does not need to change its expectations.
 */
export async function getUser(userId) {
  const result = await db.query("SELECT * FROM users WHERE user_id = $1", [userId]);
  const row = result.rows[0];
  if (!row) return null;
  return rowToUser(row);
}

/**
 * Insert or update a user.  Accepts the same object shape returned by getUser().
 */
export async function upsertUser(user) {
  const payload = userToRow(user);
  await db.query(
    `
      INSERT INTO users (
        user_id, username, call_name, email, password,
        contact_name, contact_phone, contact_name2, contact_phone2,
        last_checkin_date, last_alert_at, language, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5,
        $6, $7, $8, $9,
        $10, $11, $12, $13
      )
      ON CONFLICT(user_id) DO UPDATE SET
        username = EXCLUDED.username,
        call_name = EXCLUDED.call_name,
        email = EXCLUDED.email,
        password = EXCLUDED.password,
        contact_name = EXCLUDED.contact_name,
        contact_phone = EXCLUDED.contact_phone,
        contact_name2 = EXCLUDED.contact_name2,
        contact_phone2 = EXCLUDED.contact_phone2,
        last_checkin_date = EXCLUDED.last_checkin_date,
        last_alert_at = EXCLUDED.last_alert_at,
        language = EXCLUDED.language,
        updated_at = EXCLUDED.updated_at
    `,
    [
      payload.user_id,
      payload.username,
      payload.call_name,
      payload.email,
      payload.password,
      payload.contact_name,
      payload.contact_phone,
      payload.contact_name2,
      payload.contact_phone2,
      payload.last_checkin_date,
      payload.last_alert_at,
      payload.language,
      payload.updated_at,
    ]
  );
}

/**
 * Look up a user by email address.
 */
export async function getUserByEmail(email) {
  const result = await db.query("SELECT * FROM users WHERE email = $1", [email]);
  const row = result.rows[0];
  if (!row) return null;
  return rowToUser(row);
}

/**
 * Update a user's password hash.
 */
export async function updatePassword(userId, hashedPassword) {
  await db.query(
    "UPDATE users SET password = $1, updated_at = $2 WHERE user_id = $3",
    [hashedPassword, new Date().toISOString(), userId]
  );
}

/**
 * Retrieve all users (for the scheduler's daily scan).
 */
export async function getAllUsers() {
  const result = await db.query("SELECT * FROM users");
  const rows = result.rows;
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

function userToRow(user) {
  return {
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
    language: user.language ?? "en",
    updated_at: user.updatedAt ?? new Date().toISOString(),
  };
}
