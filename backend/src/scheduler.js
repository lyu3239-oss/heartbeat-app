import cron from "node-cron";
import { getAllUsers, upsertUser } from "./store.js";
import { shouldTriggerEmergency, placeAllEmergencyCalls } from "./alertService.js";

/**
 * Daily emergency check — runs every day at 10:00 AM (server time).
 * Scans all users; if anyone has not checked in for 2+ days,
 * automatically calls their emergency contacts via Twilio.
 */
export function startScheduler() {
    // Run at 10:00 AM every day
    cron.schedule("0 10 * * *", async () => {
        console.log(`\n⏰ [CRON] Running daily emergency check at ${new Date().toISOString()}`);

        const users = await getAllUsers();
        let alertCount = 0;

        for (const user of users) {
            if (!shouldTriggerEmergency(user.lastCheckinDate)) {
                continue;
            }

            // Skip users who were already alerted in the last 24 hours
            if (user.lastAlertAt) {
                const hoursSinceAlert = (Date.now() - new Date(user.lastAlertAt).getTime()) / (1000 * 60 * 60);
                if (hoursSinceAlert < 24) {
                    console.log(`[CRON] Skipping ${user.userId} — already alerted ${Math.round(hoursSinceAlert)}h ago`);
                    continue;
                }
            }

            console.log(`[CRON] ⚠️ User ${user.userId} (${user.username}) has not checked in for 2+ days`);

            try {
                const results = await placeAllEmergencyCalls(user);
                console.log(`[CRON] Call results for ${user.userId}:`, JSON.stringify(results));
                alertCount++;

                // Update lastAlertAt to prevent repeated calls within 24h
                user.lastAlertAt = new Date().toISOString();
                user.updatedAt = new Date().toISOString();
                await upsertUser(user);
            } catch (err) {
                console.error(`[CRON] Error calling contacts for ${user.userId}:`, err.message);
            }
        }

        console.log(`[CRON] ✅ Check complete. ${alertCount} alert(s) triggered out of ${users.length} user(s).\n`);
    });

    console.log("📅 Emergency check scheduler started (daily at 10:00 AM)");
}
