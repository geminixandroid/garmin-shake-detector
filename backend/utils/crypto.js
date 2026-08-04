const crypto = require('crypto');

// The short code is effectively a bearer token: whoever knows it gets the device_id from
// /setup. Hence randomBytes rather than Math.random(), which is predictable from earlier
// values.
function generateShortCode() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    const bytes = crypto.randomBytes(6);
    let code = '';
    for (let i = 0; i < 6; i += 1) {
        code += chars[bytes[i] % chars.length];
    }
    return code;
}

function generateSecret() {
    return crypto.randomBytes(16).toString('hex');
}

module.exports = {
    generateShortCode,
    generateSecret
};
