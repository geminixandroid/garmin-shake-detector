const db = require('../db/database');
const { generateSecret } = require('../utils/crypto');

// Registers a phone against a watch. The device row is created once; subscriptions
// accumulate, one per browser that wants alerts.
//
// An existing secret is PRESERVED. The earlier code did INSERT OR REPLACE and generated
// a fresh one, which was invisible with a single subscription - but with several, the
// second phone subscribing invalidated the secret the first phone had stored, leaving it
// unable to unsubscribe.
function registerDevice(deviceId, subscription, ip) {
    return new Promise((resolve, reject) => {
        db.get(
            'SELECT secret FROM devices WHERE device_id = ?',
            [deviceId],
            (err, existing) => {
                if (err) return reject(err);

                const secret = existing ? existing.secret : generateSecret();
                const now = new Date().toISOString();

                const afterDevice = (err2) => {
                    if (err2) return reject(err2);
                    addSubscription(deviceId, subscription)
                        .then(() => resolve({ secret }))
                        .catch(reject);
                };

                if (existing) {
                    db.run(
                        'UPDATE devices SET ip_address = ? WHERE device_id = ?',
                        [ip, deviceId],
                        afterDevice
                    );
                } else {
                    db.run(
                        `INSERT INTO devices (device_id, registered_at, secret, ip_address)
                         VALUES (?, ?, ?, ?)`,
                        [deviceId, now, secret, ip],
                        afterDevice
                    );
                }
            }
        );
    });
}

function addSubscription(deviceId, subscription) {
    return new Promise((resolve, reject) => {
        const endpoint = subscription && subscription.endpoint;
        if (!endpoint) {
            return reject(new Error('Subscription has no endpoint'));
        }
        // INSERT OR REPLACE rather than ON CONFLICT ... DO UPDATE: same effect on an
        // endpoint clash, and it does not require SQLite newer than 3.24, which matters
        // on an old host.
        db.run(
            `INSERT OR REPLACE INTO subscriptions
             (device_id, endpoint, subscription, created_at) VALUES (?, ?, ?, ?)`,
            [deviceId, endpoint, JSON.stringify(subscription), new Date().toISOString()],
            (err) => {
                if (err) return reject(err);
                resolve();
            }
        );
    });
}

// Is this id something the system has actually seen?
//
// A valid-looking id is not enough: /setup used to render a working Subscribe button for
// any string matching the character class, so anyone could invent an id and create a
// device row for a watch that does not exist. An id becomes known when the watch asks for
// a short link, which happens before anybody can reach the setup page.
function isKnownDevice(deviceId) {
    return new Promise((resolve, reject) => {
        db.get(
            `SELECT
                (SELECT COUNT(*) FROM devices WHERE device_id = ?) +
                (SELECT COUNT(*) FROM short_links WHERE device_id = ?) AS n`,
            [deviceId, deviceId],
            (err, row) => {
                if (err) return reject(err);
                resolve(!!row && row.n > 0);
            }
        );
    });
}

function getDevice(deviceId) {
    return new Promise((resolve, reject) => {
        db.get('SELECT * FROM devices WHERE device_id = ?', [deviceId], (err, row) => {
            if (err) return reject(err);
            resolve(row);
        });
    });
}

//! Every subscription of this watch, parsed - the shape web-push expects.
function getSubscriptions(deviceId) {
    return new Promise((resolve, reject) => {
        db.all(
            'SELECT endpoint, subscription FROM subscriptions WHERE device_id = ?',
            [deviceId],
            (err, rows) => {
                if (err) return reject(err);
                const result = [];
                (rows || []).forEach((row) => {
                    try {
                        result.push({
                            endpoint: row.endpoint,
                            subscription: JSON.parse(row.subscription)
                        });
                    } catch (e) {
                        // One corrupt row must not stop delivery to the other phones.
                    }
                });
                resolve(result);
            }
        );
    });
}

function countSubscriptions(deviceId) {
    return new Promise((resolve, reject) => {
        db.get(
            'SELECT COUNT(*) AS n FROM subscriptions WHERE device_id = ?',
            [deviceId],
            (err, row) => {
                if (err) return reject(err);
                resolve(row ? row.n : 0);
            }
        );
    });
}

// Detaches one browser. endpoint is required: there is deliberately no "unsubscribe
// everywhere". Phones are subscribed one at a time and turned off the same way, and a
// bulk button is mostly a way to end up with no alerts at all by accident. Purging a
// device outright is a one-line sqlite3 job on the server.
function unsubscribe(deviceId, secret, endpoint) {
    return new Promise((resolve, reject) => {
        if (!endpoint) {
            return reject(new Error('endpoint is required'));
        }
        db.get('SELECT secret FROM devices WHERE device_id = ?', [deviceId], (err, row) => {
            if (err) return reject(err);
            if (!row || row.secret !== secret) {
                return reject(new Error('Wrong secret, or device not found'));
            }
            db.run(
                'DELETE FROM subscriptions WHERE device_id = ? AND endpoint = ?',
                [deviceId, endpoint],
                (err2) => (err2 ? reject(err2) : resolve())
            );
        });
    });
}

//! Drops a subscription the push service reported as gone (404/410). No secret needed:
//! the confirmation came from the service itself, not from a user.
function removeDeadSubscription(endpoint) {
    return new Promise((resolve) => {
        db.run('DELETE FROM subscriptions WHERE endpoint = ?', [endpoint], () => resolve());
    });
}

function updateLastAlert(deviceId) {
    return new Promise((resolve, reject) => {
        db.run(
            'UPDATE devices SET last_alert_at = ? WHERE device_id = ?',
            [new Date().toISOString(), deviceId],
            (err) => {
                if (err) return reject(err);
                resolve();
            }
        );
    });
}

module.exports = {
    registerDevice,
    addSubscription,
    isKnownDevice,
    getDevice,
    getSubscriptions,
    countSubscriptions,
    unsubscribe,
    removeDeadSubscription,
    updateLastAlert
};
