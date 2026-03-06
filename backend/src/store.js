import db from "./db.js";
import { hashToken } from "./jwtUtils.js";

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
        last_checkin_date, language, updated_at, apple_user_id
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
        language = EXCLUDED.language,
        updated_at = EXCLUDED.updated_at,
        apple_user_id = COALESCE(EXCLUDED.apple_user_id, users.apple_user_id)
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
      payload.language,
      payload.updated_at,
      payload.apple_user_id,
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
 * Delete a user account by user id.
 */
export async function deleteUserById(userId) {
  await db.query("DELETE FROM users WHERE user_id = $1", [userId]);
}

/**
 * Find user by Apple User ID (for Sign in with Apple).
 */
export async function getUserByAppleId(appleUserId) {
  const result = await db.query("SELECT * FROM users WHERE apple_user_id = $1", [appleUserId]);
  const row = result.rows[0];
  if (!row) return null;
  return rowToUser(row);
}

/* ── Refresh Token CRUD ─────────────────────────────────── */

export async function saveRefreshToken(userId, token, expiresAt) {
  const tokenHash = hashToken(token);
  await db.query(
    "INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)",
    [userId, tokenHash, expiresAt]
  );
}

export async function getRefreshToken(token) {
  const tokenHash = hashToken(token);
  const result = await db.query(
    "SELECT * FROM refresh_tokens WHERE token_hash = $1 AND expires_at > NOW()",
    [tokenHash]
  );
  return result.rows[0] || null;
}

export async function deleteRefreshToken(token) {
  const tokenHash = hashToken(token);
  await db.query("DELETE FROM refresh_tokens WHERE token_hash = $1", [tokenHash]);
}

export async function deleteAllUserRefreshTokens(userId) {
  await db.query("DELETE FROM refresh_tokens WHERE user_id = $1", [userId]);
}

/* ── Verification Code CRUD ─────────────────────────────── */

export async function saveVerificationCode(email, code, expiresAt) {
  // Delete any existing codes for this email first
  await db.query("DELETE FROM verification_codes WHERE email = $1", [email]);
  await db.query(
    "INSERT INTO verification_codes (email, code, expires_at) VALUES ($1, $2, $3)",
    [email, code, expiresAt]
  );
}

export async function getVerificationCode(email) {
  const result = await db.query(
    "SELECT * FROM verification_codes WHERE email = $1 AND expires_at > NOW() ORDER BY created_at DESC LIMIT 1",
    [email]
  );
  return result.rows[0] || null;
}

export async function deleteVerificationCode(email) {
  await db.query("DELETE FROM verification_codes WHERE email = $1", [email]);
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
    language: row.language ?? 'en',
    updatedAt: row.updated_at,
    createdAt: row.created_at,
    appleUserId: row.apple_user_id,
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
    language: user.language ?? "en",
    updated_at: user.updatedAt ?? new Date().toISOString(),
    apple_user_id: user.appleUserId ?? null,
  };
}
