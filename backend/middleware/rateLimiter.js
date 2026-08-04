const rateLimit = require('express-rate-limit');

// Applied to the endpoints that write to the database and are open without
// authentication: /api/register, /api/shorten and /api/alert. Without it a public service
// can be filled with junk rows.
//
// 30 requests per 5 minutes per address is an order of magnitude above any legitimate use
// - the watch sends an alert at most once a minute, and setup happens once. It counts real
// client addresses only because server.js sets trust proxy.
const writeLimiter = rateLimit({
    windowMs: 5 * 60 * 1000,
    max: 30,
    message: { error: 'Too many requests. Try again later.' }
});

module.exports = { writeLimiter };
