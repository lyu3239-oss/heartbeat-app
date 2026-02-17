import nodemailer from "nodemailer";

function hasValue(value) {
    return typeof value === "string" && value.trim().length > 0;
}

function getConfiguredProvider() {
    const provider = (process.env.EMAIL_PROVIDER || "auto").trim().toLowerCase();
    return provider || "auto";
}

function getSmtpConfig() {
    const host = process.env.SMTP_HOST;
    const port = Number(process.env.SMTP_PORT || 587);
    const user = process.env.SMTP_USER;
    const pass = process.env.SMTP_PASS;
    const secure = String(process.env.SMTP_SECURE || "false").toLowerCase() === "true";

    if (!hasValue(host) || !hasValue(user) || !hasValue(pass)) {
        return null;
    }

    return { host, port, user, pass, secure };
}

function getResendConfig() {
    const apiKey = process.env.RESEND_API_KEY;
    if (!hasValue(apiKey)) {
        return null;
    }
    return { apiKey };
}

async function sendViaSmtp({ from, to, subject, html, text }) {
    const smtp = getSmtpConfig();
    if (!smtp) {
        return { ok: false, reason: "not_configured" };
    }

    const transporter = nodemailer.createTransport({
        host: smtp.host,
        port: smtp.port,
        secure: smtp.secure,
        auth: {
            user: smtp.user,
            pass: smtp.pass,
        },
    });

    try {
        await transporter.sendMail({
            from,
            to,
            subject,
            html,
            text,
        });
        return { ok: true };
    } catch (error) {
        console.error("[emailService] SMTP send failed:", error);
        return { ok: false, reason: "provider_error" };
    }
}

async function sendViaResend({ from, to, subject, html, text }) {
    const resend = getResendConfig();
    if (!resend) {
        return { ok: false, reason: "not_configured" };
    }

    try {
        const response = await fetch("https://api.resend.com/emails", {
            method: "POST",
            headers: {
                Authorization: `Bearer ${resend.apiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                from,
                to: [to],
                subject,
                html,
                text,
            }),
        });

        if (!response.ok) {
            const providerError = await response.text();
            console.error("[emailService] Resend send failed:", providerError);
            return { ok: false, reason: "provider_error" };
        }

        return { ok: true };
    } catch (error) {
        console.error("[emailService] Resend request failed:", error);
        return { ok: false, reason: "provider_error" };
    }
}

export async function sendEmail({ to, subject, html, text }) {
    const from = process.env.EMAIL_FROM;
    if (!hasValue(from)) {
        console.warn("[emailService] EMAIL_FROM is not configured.");
        return { ok: false, reason: "not_configured" };
    }

    const provider = getConfiguredProvider();

    if (provider === "smtp") {
        return sendViaSmtp({ from, to, subject, html, text });
    }

    if (provider === "resend") {
        return sendViaResend({ from, to, subject, html, text });
    }

    // auto: try SMTP first, then fallback to Resend
    const smtpResult = await sendViaSmtp({ from, to, subject, html, text });
    if (smtpResult.ok || smtpResult.reason === "provider_error") {
        return smtpResult;
    }

    return sendViaResend({ from, to, subject, html, text });
}
