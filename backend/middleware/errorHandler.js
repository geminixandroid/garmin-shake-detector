const { logError } = require('../utils/log');

// The path is logged alongside the message: an unhandled error says nothing useful
// on its own, and this is the one place that knows which request produced it.
function errorHandler(err, req, res, next) {
    logError('error', `${req.method} ${req.path}: ${err.message}`);
    res.status(500).json({ error: 'Internal server error' });
}

function notFound(req, res) {
    res.status(404).json({ error: 'Not found' });
}

module.exports = { errorHandler, notFound };
