import jwt from "jsonwebtoken";
import crypto from "node:crypto";

const JWT_SECRET = process.env.JWT_SECRET;
const JWT_ACCESS_EXPIRY = process.env.JWT_ACCESS_EXPIRY || "15m";
const JWT_REFRESH_EXPIRY = process.env.JWT_REFRESH_EXPIRY || "7d";

// Validate JWT_SECRET on module load
if (!JWT_SECRET) {
  throw new Error("JWT_SECRET environment variable is required");
}

if (JWT_SECRET.length < 32) {
  throw new Error("JWT_SECRET must be at least 32 characters long");
}

/**
 * Generate access token (short-lived, 15 minutes)
 */
export function generateAccessToken(userId, email) {
  return jwt.sign(
    { userId, email, type: "access" },
    JWT_SECRET,
    { expiresIn: JWT_ACCESS_EXPIRY }
  );
}

/**
 * Generate refresh token (long-lived, 7 days)
 */
export function generateRefreshToken(userId) {
  return jwt.sign(
    { userId, type: "refresh" },
    JWT_SECRET,
    { expiresIn: JWT_REFRESH_EXPIRY }
  );
}

/**
 * Verify access token
 */
export function verifyAccessToken(token) {
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    if (decoded.type !== "access") {
      throw new Error("Invalid token type");
    }
    return { valid: true, payload: decoded };
  } catch (err) {
    return { valid: false, error: err.message };
  }
}

/**
 * Verify refresh token
 */
export function verifyRefreshToken(token) {
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    if (decoded.type !== "refresh") {
      throw new Error("Invalid token type");
    }
    return { valid: true, payload: decoded };
  } catch (err) {
    return { valid: false, error: err.message };
  }
}

/**
 * Hash refresh token for database storage
 */
export function hashToken(token) {
  return crypto.createHash("sha256").update(token).digest("hex");
}
