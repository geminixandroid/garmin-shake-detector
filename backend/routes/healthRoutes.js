const express = require('express');
const router = express.Router();
const { version } = require('../package.json');

// The only endpoint that can be called without a device id and without side effects.
//
// It needs to be separate because on every other route an error is a normal answer
// (/setup without a parameter legitimately returns 400), so none of them distinguish a
// running app from a proxy that could not reach the process. A 200 with JSON here means
// the panel started the app and the request reached Express.
//
// Exposes nothing about any device, so unlike the removed /api/devices and /api/logs it
// is safe to leave open.
router.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'shakedetector',
        version,
        // Proof that trust proxy is working: behind a TLS proxy this must read https. If
        // it says http, /api/shorten will hand the watch a link Connect IQ rejects with
        // -1001.
        protocol: req.protocol,
        uptimeSeconds: Math.round(process.uptime())
    });
});

module.exports = router;
