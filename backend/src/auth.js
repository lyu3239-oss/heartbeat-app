import { Router } from "express";
import bcrypt from "bcrypt";
import { getUserByEmail, upsertUser, updatePassword } from "./store.js";
import { sendEmail } from "./emailService.js";

const router = Router();
const SALT_ROUNDS = 10;

// In-memory verification code store: email -> { code, expiresAt }
const verificationCodes = new Map();

// Helper: return message in user's language
function msg(lang, en, zh) {
    return lang === "zh" ? zh : en;
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

    const existing = getUserByEmail(email);
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
        lastAlertAt: null,
        language: lang,
        updatedAt: new Date().toISOString(),
    };

    upsertUser(user);

    const { password: _, ...safeUser } = user;
    return res.json({ ok: true, message: msg(lang, "Registration successful", "注册成功"), user: safeUser });
});

// ── Login ───────────────────────────────────────────────────
router.post("/login", async (req, res) => {
    const { email, password, language } = req.body || {};
    const lang = language || "en";

    if (!email || !password) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please enter email and password", "请填写邮箱和密码") });
    }

    const user = getUserByEmail(email);
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
        upsertUser(user);
    }

    const { password: _, ...safeUser } = user;
    return res.json({ ok: true, message: msg(lang, "Login successful", "登录成功"), user: safeUser });
});

// ── Send Verification Code ─────────────────────────────────
router.post("/send-code", async (req, res) => {
    const { email, language } = req.body || {};
    const lang = language || "en";

    if (!email) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please provide an email address", "请提供邮箱地址") });
    }

    const user = getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "This email is not registered", "该邮箱未注册") });
    }

    const code = String(Math.floor(100000 + Math.random() * 900000));
    verificationCodes.set(email, {
        code,
        expiresAt: Date.now() + 10 * 60 * 1000,
    });

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
        verificationCodes.delete(email);

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

    console.log(`\n📧 Verification code sent to ${email} (valid for 10 minutes)\n`);

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

    const stored = verificationCodes.get(email);
    if (!stored) {
        return res.status(400).json({ ok: false, message: msg(lang, "Please get a verification code first", "请先获取验证码") });
    }
    if (Date.now() > stored.expiresAt) {
        verificationCodes.delete(email);
        return res.status(400).json({ ok: false, message: msg(lang, "Code expired, please request a new one", "验证码已过期，请重新获取") });
    }
    if (stored.code !== code) {
        return res.status(400).json({ ok: false, message: msg(lang, "Invalid verification code", "验证码错误") });
    }

    const user = getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "User not found", "用户不存在") });
    }

    const hashedPassword = await bcrypt.hash(newPassword, SALT_ROUNDS);
    updatePassword(user.userId, hashedPassword);
    verificationCodes.delete(email);

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

    const user = getUserByEmail(email);
    if (!user) {
        return res.status(404).json({ ok: false, message: msg(lang, "User not found", "用户不存在") });
    }

    const match = await bcrypt.compare(currentPassword, user.password);
    if (!match) {
        return res.status(401).json({ ok: false, message: msg(lang, "Current password is incorrect", "当前密码错误") });
    }

    const hashedPassword = await bcrypt.hash(newPassword, SALT_ROUNDS);
    updatePassword(user.userId, hashedPassword);

    return res.json({ ok: true, message: msg(lang, "Password changed successfully", "密码修改成功") });
});

export default router;
