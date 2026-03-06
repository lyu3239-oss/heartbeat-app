import { verifyAccessToken } from "./jwtUtils.js";

/**
 * Authentication middleware - verifies JWT access token
 * Attaches userId and email to req.user if valid
 */
export function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return res.status(401).json({
      ok: false,
      message: "Authentication required. Please provide a valid access token."
    });
  }

  const token = authHeader.substring(7); // Remove "Bearer " prefix
  const result = verifyAccessToken(token);

  if (!result.valid) {
    return res.status(401).json({
      ok: false,
      message: "Invalid or expired access token. Please refresh your token or log in again.",
      error: result.error
    });
  }

  // Attach user info to request
  req.user = {
    userId: result.payload.userId,
    email: result.payload.email
  };

  next();
}
