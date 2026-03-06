import { Router } from "express";
import bcrypt from "bcrypt";
import dayjs from "dayjs";
import {
  deleteUserById,
  getUserByEmail,
  getUser,
  upsertUser,
  updatePassword,
  saveRefreshToken,
  getRefreshToken,
  deleteRefreshToken,
  deleteAllUserRefreshTokens,
  saveVerificationCode,
  getVerificationCode,
  deleteVerificationCode,
} from "./store.js";
import { sendEmail } from "./emailService.js";
import {
  generateAccessToken,
  generateRefreshToken,
  verifyRefreshToken,
} from "./jwtUtils.js";

const router = Router();
const SALT_ROUNDS = 10;

// Helper: return message in user's language
function msg(lang, en, zh) {
    return lang === "zh" ? zh : en;
}

// Helper: sanitize email for logging
function sanitizeEmail(email) {
    if (!email || !email.includes("@")) return "***";
    const [local, domain] = email.split("@");
    return `${local[0]}***@${domain}`;
}

// ── Register ────────────────────────────────────────────────
router.post("/register", async (req, res) => {
    const { username, email, password, language } = req.body || {};
    const lang = language || "en";

    if (!email || !password) {
        return res.status(400).json({ ok: false, message: msg(lang, "Email and password are required", "邮箱和密码为必填项") });
    }
    if (password.length < 6) {
        return res.status(400).json({ ok: false, message: msg(lang, "Password must be at least 6 characters", "密码长度至少为6位") });
    }

    const existing = await getUserByEmail(email);
    if (existing) {
        return res.status(409).json({ ok: false, message: msg(lang, "This email is already registered", "该邮箱已被注册") });
    }

    const hashedPassword = await bcrypt.hash(password, SALT_ROUNDS);
    const userId = `ios-${email.replace(/@/g, "-").replace(/\./g, "-").toLowerCase()}`;

    const user = {
        userId,
        username: username || email.split("@")[0],
        callName: username || email.split("@")[0],
        email,
        password: hashedPassword,
        emergencyContact: { name: null, phone: null },
        emergencyContact2: { name: null, phone: null },
        lastCheckinDate: null,
        language: lang,
        updatedAt: new Date().toISOString(),
    };

    await upsertUser(user);

    const accessToken = generateAccessToken(userId, email);
    const refreshToken = generateRefreshToken(userId);
    const refreshExpiresAt = dayjs().add(7, "day").toDate();
    await saveRefreshToken(userId, refreshToken, refreshExpiresAt);

    const { password: _, ...safeUser } = user;
    return res.json({
      ok: true,
      message: msg(lang, "Registration successful", "注册成功"),
      user: safeUser,
      accessToken,
      refreshToken,
    });
});

// ── Login ───────────────────────────────────────────────────
router.post("/login", async (req, res) => {
    const { email, password, language } = req.body || {};
    const lang = language || "en";

    if (!email || !password) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please enter email and password", "请填写邮箱和密码") });
    }

    const user = await getUserByEmail(email);
    if (!user) {
        return res.status(401).json({ ok: false, message: msg(lang, "Invalid email or password", "邮箱或密码错误") });
    }

    const match = await bcrypt.compare(password, user.password);
    if (!match) {
        return res.status(401).json({ ok: false, message: msg(lang, "Invalid email or password", "邮箱或密码错误") });
    }

    // Update user's language preference on login
    if (user.language !== lang) {
        user.language = lang;
        user.updatedAt = new Date().toISOString();
        await upsertUser(user);
    }

    const accessToken = generateAccessToken(user.userId, user.email);
    const refreshToken = generateRefreshToken(user.userId);
    const refreshExpiresAt = dayjs().add(7, "day").toDate();
    await saveRefreshToken(user.userId, refreshToken, refreshExpiresAt);

    const { password: _, ...safeUser } = user;
    return res.json({
      ok: true,
      message: msg(lang, "Login successful", "登录成功"),
      user: safeUser,
      accessToken,
      refreshToken,
    });
});

// ── Send Verification Code ─────────────────────────────────
router.post("/send-code", async (req, res) => {
    const { email, language } = req.body || {};
    const lang = language || "en";

    if (!email) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please provide an email address", "请提供邮箱地址") });
    }

    const user = await getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "This email is not registered", "该邮箱未注册") });
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    const expiresAt = dayjs().add(10, "minute").toDate();
    await saveVerificationCode(email, code, expiresAt);

    const subject = msg(lang, "Your Heartbeat verification code", "您的 Heartbeat 验证码");
    const html = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; line-height: 1.5;">
        <h2>${msg(lang, "Heartbeat verification code", "Heartbeat 验证码")}</h2>
        <p>${msg(lang, "Your verification code is:", "您的验证码是：")}</p>
        <p style="font-size: 24px; font-weight: bold; letter-spacing: 3px;">${code}</p>
        <p>${msg(lang, "This code expires in 10 minutes.", "验证码 10 分钟后过期。")}</p>
      </div>
    `;
    const text = `${msg(lang, "Your verification code is", "您的验证码是")}: ${code}. ${msg(lang, "It expires in 10 minutes.", "10 分钟后过期。")}`;

    const result = await sendEmail({
        to: email,
        subject,
        html,
        text,
    });

    if (!result.ok) {
        await deleteVerificationCode(email);

        if (result.reason === "not_configured") {
            return res.status(503).json({
                ok: false,
                message: msg(
                    lang,
                    "Email service is not configured yet. Please contact support.",
                    "邮件服务尚未配置，请联系管理员。"
                ),
            });
        }

        return res.status(502).json({
            ok: false,
            message: msg(
                lang,
                "Failed to send verification email. Please try again later.",
                "验证码发送失败，请稍后重试。"
            ),
        });
    }

    console.log(`\n📧 Verification code sent to ${sanitizeEmail(email)} (valid for 10 minutes)\n`);

    return res.json({ ok: true, message: msg(lang, "Verification code sent to your email", "验证码已发送到邮箱") });
});

// ── Reset Password ──────────────────────────────────────────
router.post("/reset-password", async (req, res) => {
    const { email, code, newPassword, language } = req.body || {};
    const lang = language || "en";

    if (!email || !code || !newPassword) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please fill in all fields", "请填写所有字段") });
    }
    if (newPassword.length < 6) {
        return res.status(400).json({ ok: false, message: msg(lang, "New password must be at least 6 characters", "新密码长度至少为6位") });
    }

    const stored = await getVerificationCode(email);
    if (!stored) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please get a verification code first", "请先获取验证码") });
    }
    if (stored.code !== code) {
        return res.status(400).json({ ok: false, message: msg(lang, "Invalid verification code", "验证码错误") });
    }

    const user = await getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "User not found", "用户不存在") });
    }

    const hashedPassword = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await updatePassword(user.userId, hashedPassword);
    await deleteVerificationCode(email);

    return res.json({ ok: true, message: msg(lang, "Password reset successful", "密码重置成功") });
});

// ── Change Password (authenticated) ────────────────────────
router.post("/change-password", async (req, res) => {
    const { email, currentPassword, newPassword, language } = req.body || {};
    const lang = language || "en";

    if (!email || !currentPassword || !newPassword) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please fill in all fields", "请填写所有字段") });
    }
    if (newPassword.length < 6) {
        return res.status(400).json({ ok: false, message: msg(lang, "New password must be at least 6 characters", "新密码长度至少为6位") });
    }

    const user = await getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "User not found", "用户不存在") });
    }

    const match = await bcrypt.compare(currentPassword, user.password);
    if (!match) {
        return res.status(401).json({ ok: false, message: msg(lang, "Current password is incorrect", "当前密码错误") });
    }

    const hashedPassword = await bcrypt.hash(newPassword, SALT_ROUNDS);
    await updatePassword(user.userId, hashedPassword);

    return res.json({ ok: true, message: msg(lang, "Password changed successfully", "密码修改成功") });
});

// ── Delete Account ─────────────────────────────────────────
router.post("/delete-account", async (req, res) => {
    const { email, password, language } = req.body || {};
    const lang = language || "en";

    if (!email || !password) {
        return res.status(400).json({
            ok: false,
            message: msg(lang, "Email and password are required", "邮箱和密码为必填项")
        });
    }

    const user = await getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "User not found", "用户不存在") });
    }

    const match = await bcrypt.compare(password, user.password);
    if (!match) {
        return res.status(401).json({ ok: false, message: msg(lang, "Password is incorrect", "密码错误") });
    }

    await deleteUserById(user.userId);
    await deleteAllUserRefreshTokens(user.userId);
    await deleteVerificationCode(email);

    return res.json({ ok: true, message: msg(lang, "Account deleted", "账号已删除") });
});

// ── Refresh Token ──────────────────────────────────────────
router.post("/refresh-token", async (req, res) => {
    const { refreshToken, language } = req.body || {};
    const lang = language || "en";

    if (!refreshToken) {
        return res.status(400).json({
            ok: false,
            message: msg(lang, "Refresh token is required", "刷新令牌为必填项")
        });
    }

    // Verify the refresh token
    const verification = verifyRefreshToken(refreshToken);
    if (!verification.valid) {
        return res.status(401).json({
            ok: false,
            message: msg(lang, "Invalid or expired refresh token", "刷新令牌无效或已过期")
        });
    }

    // Check if token exists in database
    const storedToken = await getRefreshToken(refreshToken);
    if (!storedToken) {
        return res.status(401).json({
            ok: false,
            message: msg(lang, "Refresh token not found or expired", "刷新令牌未找到或已过期")
        });
    }

    const userId = verification.payload.userId;
    const user = await getUser(userId);
    if (!user) {
        return res.status(404).json({
            ok: false,
            message: msg(lang, "User not found", "用户不存在")
        });
    }

    // Generate new tokens
    const newAccessToken = generateAccessToken(user.userId, user.email);
    const newRefreshToken = generateRefreshToken(user.userId);
    const refreshExpiresAt = dayjs().add(7, "day").toDate();

    // Delete old refresh token and save new one
    await deleteRefreshToken(refreshToken);
    await saveRefreshToken(user.userId, newRefreshToken, refreshExpiresAt);

    return res.json({
        ok: true,
        accessToken: newAccessToken,
        refreshToken: newRefreshToken,
    });
});

export default router;
