const webPush = require('web-push');
const deviceService = require('./deviceService');

const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY;
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY;
const VAPID_SUBJECT = process.env.VAPID_SUBJECT || 'mailto:example@example.com';

webPush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

// Fans out to EVERY subscription of this watch, independently: a failure on one phone
// must not stop delivery to the others, which for an alarm matters more than tidy error
// handling.
function sendAlertPush(deviceId, timestamp) {
    return deviceService.getSubscriptions(deviceId).then((subscriptions) => {
        if (subscriptions.length === 0) {
            return { success: false, reason: 'No subscriptions', sent: 0, failed: 0 };
        }

        const payload = JSON.stringify({
            title: '🚨 ShakeDetector Alarm!',
            body: 'Strong shaking detected. Check on the wearer.',
            data: { deviceId, timestamp }
        });

        return Promise.all(
            subscriptions.map((entry) =>
                webPush
                    .sendNotification(entry.subscription, payload)
                    .then(() => ({ ok: true }))
                    .catch((err) => {
                        // 404/410 mean the subscription is gone - revoked by the browser
                        // or wiped with the site data. Such a row has to be deleted, or
                        // it lingers forever and every send silently fails.
                        const gone = err.statusCode === 404 || err.statusCode === 410;
                        if (gone) {
                            deviceService.removeDeadSubscription(entry.endpoint);
                        }
                        return { ok: false, gone, reason: err.message };
                    })
            )
        ).then((results) => {
            const sent = results.filter((r) => r.ok).length;
            return {
                success: sent > 0,
                sent,
                failed: results.length - sent,
                removed: results.filter((r) => r.gone).length,
                reason: sent > 0 ? null : (results[0] && results[0].reason) || 'Unknown'
            };
        });
    });
}

function getVapidPublicKey() {
    return VAPID_PUBLIC_KEY;
}

module.exports = {
    sendAlertPush,
    getVapidPublicKey
};
