# Phone alert: watch side and backend

A detection is POSTed to the backend in [backend/](../backend/), which pushes a web
notification to every phone subscribed through its setup page. **The phone is an
amplifier, never a dependency**: connection failures are deliberately silent, because
an alarm app that complains about its own connectivity all night gets switched off -
a worse failure than a missed push.

## Why a server and web push

The companion has to work on iOS as well as Android. That rules out the usual trick
of running a small HTTP server on the phone and posting to it over the loopback
address, because iOS suspends background processes and will not keep a listening
socket alive. Web push is the one route that needs no native app on either platform
- at the cost that it is an ordinary notification, so it obeys silent mode and
cannot repeat until acknowledged.

If waking someone through silent mode ever becomes a requirement, a push service
with an emergency priority (Pushover, ntfy) is the next step and needs no watch-side
change beyond the URL.

## Watch side

Notes on [ShakeDetectorPhone.mc](../source/ShakeDetectorPhone.mc):

- **`SERVER_URL` must be https, and is a build-time constant.** Connect IQ refuses a
  plain http URL outright - the callback returns `-1001`
  (`SECURE_CONNECTION_REQUIRED`) before anything leaves the watch, so the server
  never sees the request. `SERVER_HOST` next to it is the same host without the
  scheme, for the setup screen to display.
- **The device id is generated on the watch** and kept in Storage, because Connect
  IQ exposes no stable per-device identifier. It is effectively a bearer token -
  whatever knows it can send alerts for this watch - and Monkey C has no
  cryptographic RNG, only `Math.rand()`. That is why the backend must not publish a
  list of device ids, and why its debug endpoints were removed.
- **No timestamp is sent**: the server stamps it. That avoids trusting the watch's
  clock, and epoch milliseconds do not fit in Monkey C's 32-bit `Number` anyway.
- **One request in flight, four second timeout, no retries.** Connect IQ has no
  per-request timeout, so a stuck request is abandoned from the 1 Hz tick -
  otherwise the in-flight flag latches and no further alert is ever sent.
- **The phone is told at most once a minute** (`ALERT_MIN_INTERVAL_SECS`), decoupled
  from the detector's 5 s repeat. The wrist should keep buzzing every 5 s - that is the
  local alarm, and the wearer may be asleep - but a one-minute event used to produce a
  dozen push notifications, which is how a phone alarm teaches its owner to swipe it
  away. The first alert after a quiet period always goes through; only repeats inside
  the window are dropped, and **Menu → Test** resets the throttle so an explicit test
  is never swallowed.
- **The setup and test screens repaint off a state counter, not an "is busy" flag.**
  Some failures return immediately with no network involved at all, so a request can
  start and fail between two ticks; a flag would never be observed as set and the
  screen would sit on "Requesting..." forever.

## Backend

Node + Express + SQLite in [backend/](../backend/). Copy `.env.example` to `.env`,
generate VAPID keys once with `npx web-push generate-vapid-keys`, then `npm install`
and `npm start`. Endpoints: `GET /api/health`, `POST /api/shorten`, `GET /s/:code`,
`GET /setup`, `POST /api/register`, `POST /api/alert`, `POST /api/unsubscribe`.
The three that write to the database are rate limited per IP.

**Several phones per watch** is supported: subscriptions live in their own table, one
row per (watch, browser) keyed uniquely on the push endpoint, and an alert fans out to
all of them. Open the same setup link on another phone and subscribe again. Two
consequences that are easy to get wrong: re-registering must **not** rotate the
device's `secret`, or the first phone's stored secret silently stops working; and
unsubscribing sends the browser's own endpoint, so it detaches that phone only.
Subscriptions the push service reports as gone (404/410) are deleted automatically,
which is also what keeps dead ones from accumulating.

### Load-bearing and easy to undo by accident

- **Two dependency versions are pinned exactly, without `^` or `~`.** The target
  host runs Node 14 with an old libstdc++: `sqlite3` above 5.0.2 needs
  `CXXABI_1.3.8` or `GLIBC_2.38` and will not load, and `web-push` from 3.6.3
  onwards declares `node >= 16`. A caret on either resolves straight back to a
  broken version - `~5.0.2` is not enough either, since the breakage is a patch
  release.
- **`app.set('trust proxy', 1)`.** Behind a TLS-terminating proxy this is what makes
  `req.protocol` report https, so `/api/shorten` hands out an https link and
  `/s/:code` redirects to https. Without it the watch gets an http URL and refuses
  it with `-1001`. It also keeps the rate limiter working on real client addresses.
- **Startup honours `LISTEN`.** Hosting panels running Passenger pass the address
  that way and proxy to it, so an app that ignores it and binds its own `PORT` looks
  dead from outside while the process is perfectly healthy. `server.js` handles
  `LISTEN` (`host:port` or a socket path), a direct `node server.js`, and being
  `require`d as a module without listening at all.
- **There is no "delete device" and no "unsubscribe everywhere".** Deleting gave nothing
  beyond unsubscribing except removing the short link - which left the watch showing a
  code that now 404s, a state with no way out for the user. It was also the only reason
  the `secret` on `/setup` was worth stealing. Unsubscribe therefore *requires* the
  browser's own endpoint and detaches that one phone. Purging a device outright is a
  one-line `sqlite3` job on the server, not a button.
- **A valid-looking device id is not enough.** `/setup` and `/api/register` both refuse an
  id the system has never seen - it becomes known when the watch asks for a short link,
  which necessarily happens before anyone can reach the setup page. Without that check any
  invented id rendered a working Subscribe button and pressing it created a device row for
  a watch that does not exist. `GET /s/:code` is rate limited for the same family of
  reasons: resolving a six-character code yields a device id.
- **The debug endpoints `GET /api/devices` and `GET /api/logs` were deliberately
  removed**, and the reason is in a comment where each used to be. Listing device
  ids closed a takeover chain: the list gave an id, `/setup?device=<id>` returns
  that device's `secret`, and `DELETE /api/device/:id` accepts it. The access model
  now is "whoever has the link controls the device", which is only honest because
  the id is unguessable.

### Accepted risks, consciously

The id is generated on the watch with `Math.rand()` seeded from the clock, so its
entropy is weaker than 32 hex characters suggest; and knowing an id is enough to
subscribe a browser or post an alert. Both are tolerable while the id stays
unpublished.

The fix if that ever changes is to split identity from authorisation: use
`System.getDeviceSettings().uniqueIdentifier` (which exists, 40 hex characters, but
is readable by any app and therefore not a secret) as the identity, drop the shared
`secret` in favour of authorising unsubscribe by the browser's own push endpoint,
and have the server issue the watch a token to send with each alert.
