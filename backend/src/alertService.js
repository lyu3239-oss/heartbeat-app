import dayjs from "dayjs";
import twilio from "twilio";
import dotenv from "dotenv";

dotenv.config({ path: "backend/.env" });

const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken = process.env.TWILIO_AUTH_TOKEN;
const fromNumber = process.env.TWILIO_FROM_NUMBER;

// Only create the Twilio client if credentials are configured.
const client = accountSid && authToken ? twilio(accountSid, authToken) : null;

function normalizeDate(value) {
  if (!value) return null;
  return dayjs(value).format("YYYY-MM-DD");
}

function escapeForXml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

/**
 * Returns true if the user has NOT checked in for 2+ days.
 */
export function shouldTriggerEmergency(lastCheckinDate) {
  const today = dayjs().startOf("day");
  const last = normalizeDate(lastCheckinDate);
  if (!last) return true;
  const diff = today.diff(dayjs(last), "day");
  return diff >= 2;
}

/**
 * Place a real phone call via Twilio to the user's emergency contact.
 * Falls back to console logging if Twilio is not configured.
 */
export async function placeEmergencyCall(user) {
  const contact = user?.emergencyContact;
  const name = contact?.name || "Unknown";
  const phone = contact?.phone || "";
  const preferredName = (user?.callName || user?.username || "your friend").trim();
  const spokenName = escapeForXml(preferredName || "your friend");
  const lang = user?.language === "zh" ? "zh-CN" : "en-US";

  if (!phone) {
    console.log("[ALERT] No emergency contact phone number configured.");
    return { ok: false, provider: "none", message: "No phone number" };
  }

  // Build TwiML based on user's language preference
  const twiml = lang === "zh-CN"
    ? [
      '<Response>',
      `  <Say language="zh-CN">您好，这是Lively应用的紧急提醒。`,
      `    您的朋友 ${spokenName} 已经超过两天没有打卡，`,
      `    请尽快联系确认其安全状况。`,
      `    重复一次，${spokenName} 已超过两天未打卡，请关注其安全。`,
      `  </Say>`,
      '  <Pause length="2"/>',
      '  <Say language="zh-CN">感谢您的关注，再见。</Say>',
      '</Response>',
    ].join("\n")
    : [
      '<Response>',
      `  <Say language="en-US">Hello, this is an emergency alert from the Lively app. `,
      `    Your friend ${spokenName} has not checked in for over two days. `,
      `    Please contact them as soon as possible to confirm their safety. `,
      `    Again, ${spokenName} has not checked in for over two days. Please check on them.`,
      `  </Say>`,
      '  <Pause length="2"/>',
      '  <Say language="en-US">Thank you for your attention. Goodbye.</Say>',
      '</Response>',
    ].join("\n");

  // ── Twilio is configured → make a real call ──────────────
  if (client && fromNumber) {
    try {
      const call = await client.calls.create({
        to: phone,
        from: fromNumber,
        twiml,
      });

      console.log(`[TWILIO] Call placed to ${name} (${phone}), SID: ${call.sid}`);
      return {
        ok: true,
        provider: "twilio",
        callSid: call.sid,
        contactName: name,
        contactPhone: phone,
      };
    } catch (err) {
      console.error(`[TWILIO_ERROR] Failed to call ${phone}:`, err.message);
      return { ok: false, provider: "twilio", error: err.message };
    }
  }

  // ── Fallback: simulate in console ────────────────────────
  console.log(`[EMERGENCY_CALL_SIMULATED] Contact: ${name}, Phone: ${phone}`);
  return {
    ok: true,
    provider: "simulated",
    contactName: name,
    contactPhone: phone,
  };
}

/**
 * Call BOTH emergency contacts if the second one is configured.
 */
export async function placeAllEmergencyCalls(user) {
  const results = [];

  // Call contact 1
  const result1 = await placeEmergencyCall(user);
  results.push({ contact: 1, ...result1 });

  // Call contact 2 if configured
  const contact2 = user?.emergencyContact2;
  if (contact2?.phone) {
    const user2 = { ...user, emergencyContact: contact2 };
    const result2 = await placeEmergencyCall(user2);
    results.push({ contact: 2, ...result2 });
  }

  return results;
}
