const sqlite3 = require('sqlite3').verbose();

const DB_PATH = process.env.DB_PATH || './shakedetector.db';

const db = new sqlite3.Database(DB_PATH);

db.serialize(() => {
    // device_id is the WATCH, not the phone. Phone subscriptions live in their own
    // table below, because one watch can have several.
    //
    // secret proves ownership and is handed out by /setup. It is created once on first
    // registration and never rotated: rotating it would invalidate the secret already
    // stored by a phone that subscribed earlier.
    db.run(`
        CREATE TABLE IF NOT EXISTS devices (
            device_id TEXT PRIMARY KEY,
            registered_at TEXT NOT NULL,
            last_alert_at TEXT,
            secret TEXT NOT NULL,
            ip_address TEXT
        )
    `);

    // One row per (watch, browser). UNIQUE on endpoint is what makes re-subscribing the
    // same browser update its row instead of adding a duplicate that would deliver every
    // alert twice.
    db.run(`
        CREATE TABLE IF NOT EXISTS subscriptions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            endpoint TEXT NOT NULL UNIQUE,
            subscription TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
    `);
    db.run('CREATE INDEX IF NOT EXISTS idx_subscriptions_device ON subscriptions(device_id)');

    // No foreign keys to devices here on purpose: the watch calls /api/shorten and
    // /api/alert before anyone has registered, so a device row need not exist yet.
    db.run(`
        CREATE TABLE IF NOT EXISTS alerts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            received_at TEXT NOT NULL
        )
    `);

    db.run(`
        CREATE TABLE IF NOT EXISTS short_links (
            short_code TEXT PRIMARY KEY,
            device_id TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
    `);
});

require('../utils/log').log('db', `ready at ${DB_PATH}`);

module.exports = db;
