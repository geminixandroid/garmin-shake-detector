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

function stamp() {
    // toISOString is 2026-08-08T10:41:03.123Z; the date and the milliseconds are
    // noise when skimming, the rest is not.
    return new Date().toISOString().replace('T', ' ').slice(0, 19) + 'Z';
}

function line(tag, message) {
    const padded = (tag + '       ').slice(0, TAG_WIDTH);
    return `${stamp()}  ${padded} ${message}`;
}

function log(tag, message) {
    console.log(line(tag, message));
}

//! Same shape, but on stderr - so a log viewer that separates the streams still
//! groups these with the errors rather than with the traffic.
function logError(tag, message) {
    console.error(line(tag, message));
}

module.exports = { log, logError };
