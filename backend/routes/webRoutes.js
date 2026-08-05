const express = require('express');
const router = express.Router();
const deviceService = require('../services/deviceService');
const pushService = require('../services/pushService');
const { validateDeviceId } = require('../utils/validators');

// No route for `/` and none for the icons: index.html, icon-32.png and icon-192.png are
// static files served by the web server. Locally (`node server.js`) they therefore 404,
// which is expected.

router.get('/setup', async (req, res) => {
    const deviceId = req.query.device;

    // deviceId is interpolated into the HTML and into a JS string literal below, so an
    // unfiltered value is script injection on the origin that hands out the secret.
    if (deviceId && !validateDeviceId(deviceId)) {
        return res.status(400).send('Invalid device id.');
    }

    if (!deviceId) {
        return res.status(400).send(`
            <!DOCTYPE html>
            <html lang="en">
            <head><meta charset="UTF-8"><title>ShakeDetector</title></head>
            <body>
                <h1>No device id</h1>
                <p>Open the link shown on your watch under Menu &rarr; Setup link.</p>
            </body>
            </html>
        `);
    }

    try {
        // Only serve setup for an id the system has seen - see isKnownDevice(). Otherwise
        // any invented id got a working Subscribe button, and pressing it created a device
        // row for a watch that does not exist.
        if (!(await deviceService.isKnownDevice(deviceId))) {
            return res.status(404).send(`
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>ShakeDetector</title>
                    <link rel="icon" type="image/png" sizes="32x32" href="/icon-32.png">
                    <style>
                        body { font-family: system-ui, sans-serif; max-width: 600px;
                               margin: 40px auto; padding: 20px; line-height: 1.5; }
                    </style>
                </head>
                <body>
                    <h1>Unknown device</h1>
                    <p>This link does not belong to any watch known to the service.</p>
                    <p>
                        Open <strong>Menu &rarr; Setup link</strong> on your watch and use
                        the code it shows.
                    </p>
                </body>
                </html>
            `);
        }

        const device = await deviceService.getDevice(deviceId);
        const secret = device?.secret || '';
        // "Registered" means at least one live subscription, not merely a row in
        // devices: the device outlives every phone unsubscribing.
        const subscriberCount = device ? await deviceService.countSubscriptions(deviceId) : 0;
        const isRegistered = subscriberCount > 0;

        res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ShakeDetector setup</title>
    <!-- Required so "Add to Home Screen" on iOS produces a standalone app rather than a
         Safari shortcut. Without standalone there is no web push there at all. -->
    <link rel="manifest" href="/manifest.webmanifest?device=${encodeURIComponent(deviceId)}">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-title" content="ShakeDetector">
    <link rel="apple-touch-icon" href="/icon-192.png">
    <link rel="icon" type="image/png" sizes="32x32" href="/icon-32.png">
    <meta name="theme-color" content="#f44336">
    <style>
        body { font-family: system-ui, sans-serif; max-width: 600px; margin: 40px auto; padding: 20px; }
        button { padding: 15px 30px; font-size: 18px; border: none; border-radius: 8px; cursor: pointer; }
        button:disabled { background: #ccc; cursor: not-allowed; }
        .status { margin-top: 20px; padding: 15px; border-radius: 8px; }
        .success { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
        .info { background: #cce5ff; color: #004085; }
        .btn-subscribe { background: #4CAF50; color: white; }
        .btn-subscribe:hover { background: #45a049; }
        .btn-unsubscribe { background: #ff9800; color: white; }
        .btn-unsubscribe:hover { background: #e68900; }
        .hidden { display: none; }
        .note { font-size: .9em; opacity: .75; }
        .section { margin-top: 30px; border-top: 1px solid #ddd; padding-top: 20px; }
    </style>
</head>
<body>
    <h1>🚨 ShakeDetector</h1>
    <p>Watch: <strong>${deviceId}</strong></p>

    <div id="deviceStatus" class="status ${isRegistered ? 'success' : 'error'}">
        ${isRegistered
            ? `✅ Notifications on. Subscribed devices: ${subscriberCount}`
            : '❌ Not set up yet. Press Subscribe.'}
    </div>
    <p class="note">
        You can subscribe several phones or browsers - the alert goes to all of them.
        Open this same link on the other device and press Subscribe.
    </p>

    <div id="subscribeSection">
        <button id="subscribeBtn" class="btn-subscribe">🔔 Subscribe to notifications</button>
    </div>

    <div id="manageSection" class="section ${isRegistered ? '' : 'hidden'}">
        <h3>Manage</h3>
        <button id="unsubscribeBtn" class="btn-unsubscribe">🔕 Turn off on this device</button>
        <p class="note">
            Affects this device only. Other subscribed devices keep receiving alerts.
        </p>
        <div id="manageStatus"></div>
    </div>

    <div id="status" class="status hidden"></div>

    <script>
        const deviceId = '${deviceId}';
        const secretFromServer = '${secret}';

        if (secretFromServer) {
            localStorage.setItem('secret_' + deviceId, secretFromServer);
        }

        const status = document.getElementById('status');
        const manageStatus = document.getElementById('manageStatus');
        const deviceStatus = document.getElementById('deviceStatus');
        const manageSection = document.getElementById('manageSection');

        if ('serviceWorker' in navigator) {
            navigator.serviceWorker.register('/sw.js');
        }

        // In a plain Safari tab on iOS, window.Notification does not exist at all: web
        // push is only available to a site added to the Home Screen and launched from
        // there. Without this check the code died on "Can't find variable: Notification"
        // and the page just looked broken.
        var supportsPush =
            'serviceWorker' in navigator &&
            'PushManager' in window &&
            'Notification' in window;
        var isIos = /iphone|ipad|ipod/i.test(navigator.userAgent) ||
            (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
        var isStandalone = window.navigator.standalone === true ||
            window.matchMedia('(display-mode: standalone)').matches;

        if (!supportsPush) {
            document.getElementById('subscribeSection').classList.add('hidden');
            status.className = 'status info';
            status.classList.remove('hidden');
            status.innerHTML = isIos && !isStandalone
                ? '<strong>Add this page to your Home Screen first.</strong><br>' +
                  'Share button &rarr; "Add to Home Screen", then open it from the ' +
                  'Home Screen and press Subscribe.<br><br>' +
                  'iOS does not allow notifications for sites opened in a Safari tab.'
                : 'This browser does not support push notifications.';
        }

        document.getElementById('subscribeBtn').addEventListener('click', async () => {
            const btn = document.getElementById('subscribeBtn');
            btn.disabled = true;
            status.className = 'status info';
            status.textContent = 'Requesting permission...';
            status.classList.remove('hidden');

            try {
                const permission = await Notification.requestPermission();
                if (permission !== 'granted') {
                    status.className = 'status error';
                    status.textContent = '❌ Permission denied.';
                    btn.disabled = false;
                    return;
                }

                const sw = await navigator.serviceWorker.ready;
                const subscription = await sw.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: '${pushService.getVapidPublicKey()}'
                });

                const response = await fetch('/api/register', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ deviceId, subscription })
                });

                const data = await response.json();

                if (response.ok) {
                    if (data.secret) {
                        localStorage.setItem('secret_' + deviceId, data.secret);
                    }
                    status.className = 'status success';
                    status.textContent = '✅ Notifications are set up.';
                    deviceStatus.className = 'status success';
                    deviceStatus.textContent = '✅ Notifications on for this device';
                    manageSection.classList.remove('hidden');
                } else {
                    throw new Error(data.error || 'Server error');
                }
            } catch (err) {
                status.className = 'status error';
                status.textContent = '❌ Error: ' + err.message;
            } finally {
                btn.disabled = false;
            }
        });

        document.getElementById('unsubscribeBtn').addEventListener('click', async () => {
            const secret = localStorage.getItem('secret_' + deviceId);
            if (!secret) {
                manageStatus.className = 'status error';
                manageStatus.textContent = '❌ No secret stored here. Subscribe again.';
                return;
            }

            manageStatus.className = 'status info';
            manageStatus.textContent = 'Turning off...';

            try {
                // Send this browser's own endpoint, so only this device is detached and
                // the others keep receiving alerts.
                let endpoint = null;
                if ('serviceWorker' in navigator) {
                    const reg = await navigator.serviceWorker.ready;
                    const existing = await reg.pushManager.getSubscription();
                    if (existing) {
                        endpoint = existing.endpoint;
                        await existing.unsubscribe();
                    }
                }

                const response = await fetch('/api/unsubscribe', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ deviceId, secret, endpoint })
                });

                const data = await response.json();
                if (response.ok) {
                    manageStatus.className = 'status success';
                    manageStatus.textContent = '✅ Notifications turned off here.';
                    deviceStatus.className = 'status error';
                    deviceStatus.textContent = '❌ Not receiving on this device';
                    manageSection.classList.add('hidden');
                } else {
                    throw new Error(data.error || 'Error');
                }
            } catch (err) {
                manageStatus.className = 'status error';
                manageStatus.textContent = '❌ Error: ' + err.message;
            }
        });
    </script>
</body>
</html>
        `);
    } catch (err) {
        res.status(500).send('Server error');
    }
});

// start_url is per device on purpose: iOS takes the launch address from the MANIFEST,
// not from the page you were on. With a fixed "/" the Home Screen icon opened the
// landing page instead of setup, so there was no way to reach the Subscribe button.
router.get('/manifest.webmanifest', (req, res) => {
    const deviceId = req.query.device;
    const startUrl = validateDeviceId(deviceId)
        ? `/setup?device=${encodeURIComponent(deviceId)}`
        : '/';

    res.type('application/manifest+json');
    res.json({
        name: 'ShakeDetector',
        short_name: 'ShakeDetector',
        description: 'Alerts from a shake detector running on a Garmin watch',
        start_url: startUrl,
        scope: '/',
        display: 'standalone',
        background_color: '#ffffff',
        theme_color: '#f44336',
        icons: [
            { src: '/icon-192.png', sizes: '192x192', type: 'image/png' }
        ]
    });
});

router.get('/sw.js', (req, res) => {
    res.type('application/javascript');
    res.send(`
        self.addEventListener('push', (event) => {
            const data = event.data ? event.data.json() : {};
            const options = {
                body: data.body || 'Alert from your watch',
                icon: '/icon-192.png',
                badge: '/icon-192.png',
                vibrate: [200, 100, 200],
                data: data.data || {},
                requireInteraction: true
            };
            event.waitUntil(
                self.registration.showNotification(data.title || 'ShakeDetector', options)
            );
        });

        self.addEventListener('notificationclick', (event) => {
            event.notification.close();

            // deviceId rides along in the push payload, so the click can land on the
            // setup page of the watch that actually fired - opening "/" left the user
            // on the landing page with nothing to act on.
            var data = event.notification.data || {};
            var url = data.deviceId
                ? '/setup?device=' + encodeURIComponent(data.deviceId)
                : '/';

            event.waitUntil(
                clients.matchAll({ type: 'window', includeUncontrolled: true })
                    .then(function (list) {
                        // Reuse a window already showing this device, otherwise every
                        // alert piles up another tab (or another PWA screen on iOS).
                        for (var i = 0; i < list.length; i++) {
                            var client = list[i];
                            if (client.url.indexOf(url) !== -1 && 'focus' in client) {
                                return client.focus();
                            }
                        }
                        return clients.openWindow(url);
                    })
            );
        });
    `);
});

module.exports = router;
