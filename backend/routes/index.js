const express = require('express');
const router = express.Router();

const healthRoutes = require('./healthRoutes');
const deviceRoutes = require('./deviceRoutes');
const alertRoutes = require('./alertRoutes');
const linkRoutes = require('./linkRoutes');
const webRoutes = require('./webRoutes');

router.use('/api', healthRoutes);
router.use('/api', deviceRoutes);
router.use('/api', alertRoutes);
router.use('/api', linkRoutes);
// linkRoutes is mounted twice on purpose: POST /api/shorten belongs under /api, but the
// link handed to the watch is /s/<code> with no prefix - it has to be short enough to
// read off a watch screen and type into a phone.
router.use('/', linkRoutes);
router.use('/', webRoutes);

module.exports = router;
