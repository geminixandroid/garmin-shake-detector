require('dotenv').config();
const express = require('express');
const routes = require('./routes');
const { errorHandler, notFound } = require('./middleware/errorHandler');
const { log } = require('./utils/log');

const app = express();

// Behind a TLS-terminating proxy (nginx, Passenger, Cloudflare) two things break quietly
// without this: req.ip becomes the proxy's address for everyone, which defeats the rate
// limiter; and req.protocol reports http, so /api/shorten hands out an http link and
// /s/:code redirects to http - which Connect IQ refuses outright with
// SECURE_CONNECTION_REQUIRED.
//
// 1 = trust exactly one hop. Do not widen this to `true` without knowing how many proxies
// are in front, or clients can spoof X-Forwarded-For and evade the limiter.
app.set('trust proxy', 1);

app.use(express.json());
app.use('/', routes);
app.use(notFound);
app.use(errorHandler);

// Three branches, because three different things may start this:
//
// 1. LISTEN - set by a hosting panel (Passenger / Node.js selector). It is "host:port",
//    sometimes a unix socket path. Ignoring it is not an option: the panel proxies to that
//    address, so an app bound to its own PORT looks dead from outside while the process is
//    perfectly healthy.
// 2. require.main === module - a plain `node server.js` by hand.
// 3. Neither: the file was required as a module (some Passenger setups, or supertest).
//    Then it must not listen at all - app is exported below and the caller starts it.
if (process.env.LISTEN) {
    const lastColon = process.env.LISTEN.lastIndexOf(':');
    if (lastColon === -1) {
        app.listen(process.env.LISTEN, () => {
            log('server', `listening on socket ${process.env.LISTEN}`);
        });
    } else {
        const host = process.env.LISTEN.slice(0, lastColon);
        const port = parseInt(process.env.LISTEN.slice(lastColon + 1), 10);
        app.listen(port, host, () => {
            log('server', `listening on ${process.env.LISTEN}`);
        });
    }
} else if (require.main === module) {
    const port = process.env.PORT || 3000;
    app.listen(port, () => {
        log('server', `listening on port ${port}`);
    });
} else {
    log('server', 'required as a module - not starting a listener');
}

module.exports = app;
