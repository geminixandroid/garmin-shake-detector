const express = require('express');
const router = express.Router();
const linkService = require('../services/linkService');
const { writeLimiter } = require('../middleware/rateLimiter');
const { validateDeviceId } = require('../utils/validators');
const { log } = require('../utils/log');

router.post('/shorten', writeLimiter, async (req, res) => {
    try {
        const { deviceId } = req.body;

        if (!validateDeviceId(deviceId)) {
            return res.status(400).json({ error: 'deviceId is required' });
        }

        const shortCode = await linkService.createShortLink(deviceId);
        const baseUrl = `${req.protocol}://${req.get('host')}`;
        const shortUrl = `${baseUrl}/s/${shortCode}`;

        log('link', `${deviceId} code=${shortCode}`);
        res.json({ shortUrl, shortCode });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Rate limited even though it only reads: a short code is six characters, and resolving
// one yields a device_id, which /setup will then trade for that device's secret. Guessing
// 36^6 over HTTP is impractical anyway, but this is the one route where guessing was free.
router.get('/s/:code', writeLimiter, async (req, res) => {
    try {
        const row = await linkService.getDeviceByShortCode(req.params.code);

        if (!row) {
            return res.status(404).send('Link not found');
        }

        res.redirect(`${req.protocol}://${req.get('host')}/setup?device=${row.device_id}`);
    } catch (err) {
        res.status(500).send('Server error');
    }
});

module.exports = router;
