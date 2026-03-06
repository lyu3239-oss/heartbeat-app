import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import dotenv from "dotenv";
import path from "node:path";
import { fileURLToPath } from "node:url";
import dayjs from "dayjs";
import { getUser, upsertUser } from "./store.js";
import authRouter from "./auth.js";
import { authMiddleware } from "./authMiddleware.js";
import { initDb } from "./db.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, "../.env") });

const app = express();
const port = Number(process.env.PORT || 4000);

// Security middleware
app.use(helmet());

// CORS configuration
const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(",").map(o => o.trim())
  : ["http://localhost:3000", "http://localhost:4000"];

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, Postman, etc.)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error("Not allowed by CORS"));
    }
  },
  credentials: true,
}));

// Rate limiters
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5, // 5 requests per window
  message: { ok: false, message: "Too many attempts, please try again later." },
  standardHeaders: true,
  legacyHeaders: false,
});

const verificationCodeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 3, // 3 requests per window
  message: { ok: false, message: "Too many verification code requests, please try again later." },
  standardHeaders: true,
  legacyHeaders: false,
});

app.use(express.json());

function renderLegalPage({ title, updatedAt, sections }) {
  const sectionHtml = sections
    .map(
      (section) => `
      <section>
        <h2>${section.heading}</h2>
        ${section.paragraphs.map((p) => `<p>${p}</p>`).join("\n")}
      </section>`
    )
    .join("\n");

  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${title} - Heartbeat</title>
    <style>
      body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #f7f8fb; color: #1a1a1a; }
      main { max-width: 860px; margin: 0 auto; padding: 40px 20px 56px; }
      h1 { margin: 0 0 8px; font-size: 32px; }
      .updated { color: #666; margin-bottom: 28px; }
      section { background: #fff; border-radius: 12px; padding: 18px 18px 6px; margin-bottom: 14px; box-shadow: 0 1px 2px rgba(0,0,0,.04); }
      h2 { margin: 0 0 8px; font-size: 18px; }
      p { margin: 0 0 12px; line-height: 1.6; }
      a { color: #0a66c2; text-decoration: none; }
      a:hover { text-decoration: underline; }
      footer { margin-top: 26px; color: #666; font-size: 14px; }
    </style>
  </head>
  <body>
    <main>
      <h1>${title}</h1>
      <p class="updated">Last updated: ${updatedAt}</p>
      ${sectionHtml}
      <footer>
        Questions? Contact us at <a href="mailto:support@heartbeatapp.space">support@heartbeatapp.space</a>.
      </footer>
    </main>
  </body>
</html>`;
}

app.use(cors());
app.use(express.json());

// Apply rate limiters to auth routes
app.use("/api/auth/register", authLimiter);
app.use("/api/auth/login", authLimiter);
app.use("/api/auth/send-code", verificationCodeLimiter);

app.use("/api/auth", authRouter);

app.get("/health", (req, res) => {
  res.json({ ok: true, service: "heartbeat-backend", time: new Date().toISOString() });
});

app.get("/terms", (req, res) => {
  res.type("html").send(
    renderLegalPage({
      title: "Terms of Service",
      updatedAt: "2026-02-21",
      sections: [
        {
          heading: "1. Acceptance",
          paragraphs: [
            "By using Heartbeat, you agree to these Terms of Service. If you do not agree, please do not use the app.",
            "You must be at least 18 years old, or use the app with permission from a legal guardian."
          ]
        },
        {
          heading: "2. Service Description",
          paragraphs: [
            "Heartbeat helps users perform daily check-ins and set emergency contacts.",
            "Heartbeat is a wellness and reminder tool, not a medical device, emergency dispatch system, or replacement for 120/911 and other emergency services."
          ]
        },
        {
          heading: "3. User Responsibilities",
          paragraphs: [
            "You are responsible for providing accurate account and emergency contact information.",
            "You must keep your contact details and emergency settings up to date.",
            "You agree not to misuse the service, interfere with operations, or attempt unauthorized access."
          ]
        },
        {
          heading: "4. Availability and Changes",
          paragraphs: [
            "We may update, suspend, or discontinue parts of the service at any time.",
            "We do not guarantee uninterrupted availability."
          ]
        },
        {
          heading: "5. Limitation of Liability",
          paragraphs: [
            "To the maximum extent permitted by law, Heartbeat and its operators are not liable for indirect, incidental, special, or consequential damages.",
            "You understand that reminder failures, delivery delays, network issues, and third-party outages may affect alerts and notifications."
          ]
        },
        {
          heading: "6. Termination",
          paragraphs: [
            "We may suspend or terminate access if these terms are violated or if required by law.",
            "You may stop using Heartbeat at any time."
          ]
        },
        {
          heading: "7. Contact",
          paragraphs: [
            "If you have questions about these Terms, contact support@heartbeatapp.space."
          ]
        }
      ]
    })
  );
});

app.get("/privacy", (req, res) => {
  res.type("html").send(
    renderLegalPage({
      title: "Privacy Policy",
      updatedAt: "2026-02-21",
      sections: [
        {
          heading: "1. Information We Collect",
          paragraphs: [
            "We collect information you provide directly, such as email, username, emergency contacts, and optional call name.",
            "With your permission, the app may access motion data (for auto check-in features) and photos (for profile avatar selection)."
          ]
        },
        {
          heading: "2. How We Use Information",
          paragraphs: [
            "We use your information to provide account access, check-in features, reminders, and emergency contact workflows.",
            "We may use limited operational data for reliability, abuse prevention, and service improvement."
          ]
        },
        {
          heading: "3. Sharing",
          paragraphs: [
            "We do not sell personal information.",
            "We only share data with service providers needed to operate Heartbeat (for example hosting, messaging, or email providers), or when required by law."
          ]
        },
        {
          heading: "4. Retention and Security",
          paragraphs: [
            "We retain data only as long as necessary for service operation, legal obligations, and dispute resolution.",
            "We use reasonable safeguards, but no system can be guaranteed 100% secure."
          ]
        },
        {
          heading: "5. Your Choices",
          paragraphs: [
            "You can update account details inside the app.",
            "You can delete your account directly in the app settings.",
            "You can revoke app permissions in iOS Settings at any time.",
            "For additional support, contact support@heartbeatapp.space."
          ]
        },
        {
          heading: "6. Children",
          paragraphs: [
            "Heartbeat is not intended for children under 13."
          ]
        },
        {
          heading: "7. Policy Updates",
          paragraphs: [
            "We may update this Privacy Policy periodically. Continued use after updates means you accept the revised policy."
          ]
        }
      ]
    })
  );
});

app.post("/api/user/register", authMiddleware, async (req, res) => {
  const { emergencyContact, emergencyContact2, callName } = req.body || {};
  const userId = req.user.userId; // From JWT token

  if (!emergencyContact?.name || !emergencyContact?.phone) {
    return res.status(400).json({
      ok: false,
      message: "emergencyContact.name and emergencyContact.phone are required"
    });
  }

  const existing = (await getUser(userId)) || {};

  const user = {
    ...existing,
    userId,
    callName: typeof callName === "string" ? callName.trim() : existing.callName,
    emergencyContact,
    emergencyContact2: emergencyContact2 || existing.emergencyContact2 || {},
    lastCheckinDate: existing.lastCheckinDate || null,
    updatedAt: new Date().toISOString()
  };

  await upsertUser(user);
  return res.json({ ok: true, user });
});

app.post("/api/user/call-name", authMiddleware, async (req, res) => {
  const { callName } = req.body || {};
  const userId = req.user.userId;

  const user = await getUser(userId);
  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found" });
  }

  const trimmedCallName = typeof callName === "string" ? callName.trim() : "";
  if (!trimmedCallName) {
    return res.status(400).json({ ok: false, message: "callName is required" });
  }

  user.callName = trimmedCallName;
  user.updatedAt = new Date().toISOString();
  await upsertUser(user);

  return res.json({ ok: true, message: "Call name updated", user });
});

app.post("/api/checkin", authMiddleware, async (req, res) => {
  const userId = req.user.userId;

  const user = await getUser(userId);

  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found. Register first." });
  }

  user.lastCheckinDate = dayjs().format("YYYY-MM-DD");
  user.updatedAt = new Date().toISOString();
  await upsertUser(user);

  return res.json({ ok: true, message: "Check-in successful", user });
});

app.get("/api/status/:userId", authMiddleware, async (req, res) => {
  const { userId } = req.params;

  // Verify the user is requesting their own status
  if (userId !== req.user.userId) {
    return res.status(403).json({ ok: false, message: "Forbidden: You can only access your own status" });
  }

  const user = await getUser(userId);

  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found" });
  }

  return res.json({
    ok: true,
    user
  });
});

async function startServer() {
  // Validate required environment variables
  if (!process.env.DATABASE_URL) {
    console.error("ERROR: DATABASE_URL environment variable is required");
    process.exit(1);
  }

  if (!process.env.JWT_SECRET) {
    console.error("ERROR: JWT_SECRET environment variable is required");
    process.exit(1);
  }

  if (process.env.JWT_SECRET.length < 32) {
    console.error("ERROR: JWT_SECRET must be at least 32 characters long");
    process.exit(1);
  }

  await initDb();

  app.listen(port, () => {
    console.log(`Heartbeat backend running at http://localhost:${port}`);
  });
}

startServer().catch((err) => {
  console.error("Failed to start server:", err);
  process.exit(1);
});
