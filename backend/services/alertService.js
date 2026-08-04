const db = require('../db/database');

function saveAlert(deviceId, timestamp) {
    return new Promise((resolve, reject) => {
        db.run(
            'INSERT INTO alerts (device_id, timestamp, received_at) VALUES (?, ?, ?)',
            [deviceId, timestamp, new Date().toISOString()],
            (err) => {
                if (err) return reject(err);
                resolve();
            }
        );
    });
}

// getAlerts() went with the GET /api/logs endpoint - it exposed every device id the same
// way the removed GET /api/devices did.

module.exports = {
    saveAlert
};
