const fs = require('fs');
const path = require('path');

// One line per event, one shape for every line. Mirrors writeLog() on the watch
// (source/ShakeDetectorCommon.mc), so both halves of the project read the same way.
//
//   2026-08-08 10:41:03Z  alert   a3f9... push sent 1/1
//   2026-08-08 10:41:03Z  alert   a3f9... push NOT sent: No subscriptions
//   2026-08-08 10:40:58Z  server  listening on 127.0.0.1:3000
//
// Three decisions worth keeping:
//
// 1. Every line carries its OWN timestamp. In production this output goes through
//    Passenger into Apache's error log, which prefixes lines with "App <pid>
//    output:" and does not reliably stamp them. Without a stamp here there is no way
//    to tell when anything happened.
//
// 2. UTC, not local. The server's timezone is not something this code knows, and an
//    unlabelled local time is a trap when correlating with anything else.
//
// 3. A fixed-width tag column. It makes the log skimmable by eye and greppable by
//    subsystem without a regex.
const TAG_WIDTH = 7;

// Written in addition to stdout/stderr, not instead: the console copy is what the
// hosting panel shows, the file is what survives at a path you can predict. Set
// LOG_PATH to an empty string to keep console output only.
//
// SECURITY: the default sits next to the database, which on the deployment host is
// inside the web root. Every line carries a device_id, and a device_id is a bearer
// token - anything that knows one can post alerts for that watch. The .htaccess must
// therefore deny .log the same way it already denies .db. If in doubt, point LOG_PATH
// somewhere above public_html instead.
const LOG_PATH = process.env.LOG_PATH === undefined
    ? './shakedetector.log'
    : process.env.LOG_PATH;

// Rotate at a megabyte, keep one generation. Shared hosting has a disk quota and no
// logrotate you control, and an alarm server that fills the quota stops being an
// alarm server. One old file is enough to look back through an incident.
const MAX_BYTES = 1024 * 1024;

let fileBroken = false;

function stamp() {
    // toISOString is 2026-08-08T10:41:03.123Z; the date and the milliseconds are
    // noise when skimming, the rest is not.
    return new Date().toISOString().replace('T', ' ').slice(0, 19) + 'Z';
}

function format(tag, message) {
    const padded = (tag + '       ').slice(0, TAG_WIDTH);
    return `${stamp()}  ${padded} ${message}`;
}

//! Appends one line to LOG_PATH, and never lets a logging problem reach the caller.
//! A full disk, a read-only mount or a missing directory must not take down an alarm
//! server - the console copy still goes out either way.
function appendToFile(text) {
    if (!LOG_PATH || fileBroken) {
        return;
    }
    try {
        // statSync before the write rather than an in-process byte counter: Passenger
        // stops the app when it goes idle, so a counter would reset several times a
        // day and the cap would never be reached.
        let size = 0;
        try {
            size = fs.statSync(LOG_PATH).size;
        } catch (e) {
            // No file yet - the first append creates it.
        }
        if (size >= MAX_BYTES) {
            fs.renameSync(LOG_PATH, LOG_PATH + '.1');
        }
        fs.appendFileSync(LOG_PATH, text + '\n');
    } catch (err) {
        // Announce once on the console, then stay quiet: a broken log path would
        // otherwise print a failure for every line it fails to write.
        fileBroken = true;
        console.error(
            format('log', `file logging disabled - ${path.resolve(LOG_PATH)}: ${err.message}`)
        );
    }
}

function log(tag, message) {
    const text = format(tag, message);
    console.log(text);
    appendToFile(text);
}

//! Same shape, but on stderr - so a log viewer that separates the streams still
//! groups these with the errors rather than with the traffic.
function logError(tag, message) {
    const text = format(tag, message);
    console.error(text);
    appendToFile(text);
}

module.exports = { log, logError };
