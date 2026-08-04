function errorHandler(err, req, res, next) {
    console.error('❌ Error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
}

function notFound(req, res) {
    res.status(404).json({ error: 'Not found' });
}

module.exports = { errorHandler, notFound };
