// A restricted character set, not "any non-empty string".
//
// device_id ends up in the HTML of /setup and inside a JS string literal there, so
// allowing anything means script injection on the very origin that hands out the secret.
// Filtering at the entrance is more reliable than escaping in the template, which is easy
// to forget on the next edit.
const DEVICE_ID_PATTERN = /^[A-Za-z0-9_-]{3,64}$/;

function validateDeviceId(deviceId) {
    return typeof deviceId === 'string' && DEVICE_ID_PATTERN.test(deviceId);
}

function validateSubscription(subscription) {
    return subscription && subscription.endpoint && subscription.keys;
}

module.exports = {
    validateDeviceId,
    validateSubscription
};
