const db = require('../db/database');
const { generateShortCode } = require('../utils/crypto');

const MAX_ATTEMPTS = 10;

// Returns the device's existing code, and only mints one if it has none.
//
// Idempotency is a requirement, not an optimisation: the watch asks every time its setup
// screen opens, and without this the same watch got a different code each time. To the
// owner that reads as a malfunction - the code they wrote down a minute ago is no longer
// the right one - and short_links grew a row per visit to the menu.
function createShortLink(deviceId) {
    return new Promise((resolve, reject) => {
        db.get(
            'SELECT short_code FROM short_links WHERE device_id = ? LIMIT 1',
            [deviceId],
            (err, existing) => {
                if (err) return reject(err);
                if (existing) return resolve(existing.short_code);

                let attempts = 0;

                function tryGenerate() {
                    const shortCode = generateShortCode();

                    db.get(
                        'SELECT short_code FROM short_links WHERE short_code = ?',
                        [shortCode],
                        (err2, taken) => {
                            if (err2) return reject(err2);
                            if (taken) {
                                attempts += 1;
                                if (attempts >= MAX_ATTEMPTS) {
                                    return reject(new Error('Could not generate a unique code'));
                                }
                                return tryGenerate();
                            }

                            db.run(
                                `INSERT INTO short_links (short_code, device_id, created_at)
                                 VALUES (?, ?, ?)`,
                                [shortCode, deviceId, new Date().toISOString()],
                                (err3) => {
                                    if (err3) return reject(err3);
                                    resolve(shortCode);
                                }
                            );
                        }
                    );
                }

                tryGenerate();
            }
        );
    });
}

function getDeviceByShortCode(shortCode) {
    return new Promise((resolve, reject) => {
        db.get(
            'SELECT device_id FROM short_links WHERE short_code = ?',
            [shortCode],
            (err, row) => {
                if (err) return reject(err);
                resolve(row);
            }
        );
    });
}

module.exports = {
    createShortLink,
    getDeviceByShortCode
};
