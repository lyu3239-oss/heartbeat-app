import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import dayjs from "dayjs";
import { getUser, upsertUser } from "./store.js";
import { placeAllEmergencyCalls, shouldTriggerEmergency } from "./alertService.js";
import authRouter from "./auth.js";
import { startScheduler } from "./scheduler.js";

dotenv.config({ path: "backend/.env" });

const app = express();
const port = Number(process.env.PORT || 4000);

app.use(cors());
app.use(express.json());
app.use("/api/auth", authRouter);

app.get("/health", (req, res) => {
  res.json({ ok: true, service: "heartbeat-backend", time: new Date().toISOString() });
});

app.post("/api/user/register", (req, res) => {
  const { userId, emergencyContact, emergencyContact2, callName } = req.body || {};
  if (!userId || !emergencyContact?.name || !emergencyContact?.phone) {
    return res.status(400).json({
      ok: false,
      message: "userId, emergencyContact.name and emergencyContact.phone are required"
    });
  }

  const existing = getUser(userId) || {};

  const user = {
    ...existing,
    userId,
    callName: typeof callName === "string" ? callName.trim() : existing.callName,
    emergencyContact,
    emergencyContact2: emergencyContact2 || existing.emergencyContact2 || {},
    lastCheckinDate: existing.lastCheckinDate || null,
    lastAlertAt: existing.lastAlertAt || null,
    updatedAt: new Date().toISOString()
  };

  upsertUser(user);
  return res.json({ ok: true, user });
});

app.post("/api/user/call-name", (req, res) => {
  const { userId, callName } = req.body || {};

  if (!userId) {
    return res.status(400).json({ ok: false, message: "userId is required" });
  }

  const user = getUser(userId);
  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found" });
  }

  const trimmedCallName = typeof callName === "string" ? callName.trim() : "";
  if (!trimmedCallName) {
    return res.status(400).json({ ok: false, message: "callName is required" });
  }

  user.callName = trimmedCallName;
  user.updatedAt = new Date().toISOString();
  upsertUser(user);

  return res.json({ ok: true, message: "Call name updated", user });
});

app.post("/api/checkin", (req, res) => {
  const { userId } = req.body || {};
  if (!userId) {
    return res.status(400).json({ ok: false, message: "userId is required" });
  }

  const user = getUser(userId);

  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found. Register first." });
  }

  user.lastCheckinDate = dayjs().format("YYYY-MM-DD");
  user.updatedAt = new Date().toISOString();
  upsertUser(user);

  return res.json({ ok: true, message: "Check-in successful", user });
});

app.get("/api/status/:userId", (req, res) => {
  const { userId } = req.params;
  const user = getUser(userId);

  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found" });
  }

  const emergency = shouldTriggerEmergency(user.lastCheckinDate);

  return res.json({
    ok: true,
    user,
    emergencyShouldTrigger: emergency
  });
});

app.post("/api/evaluate", async (req, res) => {
  const { userId } = req.body || {};
  if (!userId) {
    return res.status(400).json({ ok: false, message: "userId is required" });
  }

  const user = getUser(userId);
  if (!user) {
    return res.status(404).json({ ok: false, message: "User not found" });
  }

  const emergency = shouldTriggerEmergency(user.lastCheckinDate);
  if (!emergency) {
    return res.json({ ok: true, triggered: false, message: "No emergency needed" });
  }

  const results = await placeAllEmergencyCalls(user);
  user.lastAlertAt = new Date().toISOString();
  user.updatedAt = new Date().toISOString();
  upsertUser(user);

  return res.json({ ok: true, triggered: true, results });
});

app.listen(port, () => {
  console.log(`Heartbeat backend running at http://localhost:${port}`);
  startScheduler();
});
