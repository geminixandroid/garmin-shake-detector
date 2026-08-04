const express = require('express');
const router = express.Router();
const alertService = require('../services/alertService');
const deviceService = require('../services/deviceService');
const pushService = require('../services/pushService');
const { writeLimiter } = require('../middleware/rateLimiter');
const { validateDeviceId } = require('../utils/validators');

router.post('/alert', writeLimiter, async (req, res) => {
    try {
        const { deviceId, timestamp } = req.body;

        if (!validateDeviceId(deviceId)) {
            return res.status(400).json({ error: 'deviceId is required' });
        }

        // The watch does not send a timestamp: its clock may be wrong, and epoch
        // milliseconds do not fit in Monkey C's 32-bit Number anyway.
        const alertTimestamp = timestamp || Date.now();

        await alertService.saveAlert(deviceId, alertTimestamp);
        await deviceService.updateLastAlert(deviceId);

        // Pushing does not block the response: the watch must not wait on the phone.
        pushService.sendAlertPush(deviceId, alertTimestamp)
            .then(result => {
                if (result.success) {
                    console.log(`📨 Push sent: ${result.sent}, failed: ${result.failed}`);
                } else {
                    console.log(`⚠️ Push not sent: ${result.reason}`);
                }
                if (result.removed) {
                    console.log(`🧹 Dead subscriptions removed: ${result.removed}`);
                }
            })
            .catch(err => console.error('❌ Push error:', err.message));

        res.json({ success: true, message: 'Alert received' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET /logs was removed deliberately: it listed every device id along with the alert
// history, the same exposure as the removed GET /devices by another route. The data is
// still in the alerts table, readable with sqlite3 on the server.

module.exports = router;
