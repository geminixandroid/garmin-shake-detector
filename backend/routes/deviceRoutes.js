const express = require('express');
const router = express.Router();
const deviceService = require('../services/deviceService');
const { writeLimiter } = require('../middleware/rateLimiter');
const { validateDeviceId, validateSubscription } = require('../utils/validators');

// Registers a phone against a watch. Called again from the same browser it updates that
// subscription; from another browser it adds one - several phones per watch is supported.
router.post('/register', writeLimiter, async (req, res) => {
    try {
        const { deviceId, subscription } = req.body;

        if (!validateDeviceId(deviceId)) {
            return res.status(400).json({ error: 'Invalid deviceId' });
        }
        if (!validateSubscription(subscription)) {
            return res.status(400).json({ error: 'Invalid subscription' });
        }
        // The same rule the setup page enforces: registering is only allowed for an id the
        // watch has already announced by asking for a short link. Without this the API
        // remained open to inventing devices even after the page stopped serving them.
        if (!(await deviceService.isKnownDevice(deviceId))) {
            return res.status(404).json({ error: 'Unknown device' });
        }

        const result = await deviceService.registerDevice(
            deviceId,
            subscription,
            req.ip || req.connection.remoteAddress
        );

        res.json({ success: true, ...result });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// endpoint is required - see the comment on deviceService.unsubscribe() for why there is
// no bulk "unsubscribe everywhere".
router.post('/unsubscribe', async (req, res) => {
    try {
        const { deviceId, secret, endpoint } = req.body;

        if (!validateDeviceId(deviceId) || !secret || !endpoint) {
            return res
                .status(400)
                .json({ error: 'deviceId, secret and endpoint are required' });
        }

        await deviceService.unsubscribe(deviceId, secret, endpoint);
        res.json({ success: true, message: 'Notifications turned off' });
    } catch (err) {
        res.status(403).json({ error: err.message });
    }
});

// DELETE /device/:deviceId was removed deliberately. Beyond unsubscribing it only dropped
// the short link, leaving the watch showing a code that now 404s. It was also the sole
// reason /setup had to put the secret into the page, which is what made that secret worth
// stealing. Purging a device is a one-line sqlite3 job on the server.
//
// GET /devices was removed for the same family of reasons: a public list of device ids
// closed a takeover chain, because /setup?device=<id> returns that device's secret.

module.exports = router;
