# ShakeDetector

A Garmin Connect IQ watch app that reads the accelerometer and detects sustained,
rhythmic, high-amplitude shaking of the wrist, alerting with vibration, a tone and
the backlight.

**Detection runs entirely on the watch** - no phone, no network, nothing to pair.
A phone can optionally be notified as well, purely as a louder speaker; if it is
absent the watch behaves exactly the same.

Live instance: **<https://shakedetector.geminixandroid.com/>** - the landing page explains
the setup flow to a wearer. The watch reaches it through `SERVER_URL` in
[ShakeDetectorPhone.mc](source/ShakeDetectorPhone.mc); point that at your own host to run
your own.

This repository holds both halves: the Connect IQ app in [source/](source/) and the Node
server in [backend/](backend/).

> **This is a personal, experimental project. It is NOT a medical device and has
> not been clinically validated.** The algorithm is a crude amplitude-threshold
> counter, not a validated seizure detector. Do not rely on it to detect a
> seizure or any other medical event, and do not treat it as a substitute for
> medical supervision.

## What it looks like

One layout for every device - no app name anywhere, five things in the same order:

```
  14:32         87%  <- clock, and battery to its right
 - - - - - - - - -   <- dashed line: the alarm threshold (8)
 ▁▁▂▅█▆▂▁▁           <- window total, one bar per second, newest on the right
     OK              <- status: OK / ALARM / MUTE / MUTE! / SILENT
                        (shows the app version for the first 5 s after launch)
  ((|)) ((o  ☼       <- indicator row: which alert channels are armed
                        (struck-through speaker = nothing can alert)
```

Instinct-shaped watches (semi-octagon display) have a small round sub-window in the
top right corner, so there the battery goes inside it, the clock shifts left to
clear it, and the chart starts lower down where the full width is free again. That
is the entire difference - three fractions in
[ShakeDetectorLayout.mc](source/ShakeDetectorLayout.mc), not a second layout class.

### The chart

The bars are not raw acceleration - they are the **window total**, i.e. the exact
number the alarm compares against `CROSSING_ALARM_COUNT`, and the dashed line is
that threshold. So the chart shows the decision variable approaching the decision
line, which is what makes the tuning notes further down actionable: if the bars
regularly brush the line while you are just walking, raise the threshold.

The y axis is fixed at twice the threshold and never auto-scales - an auto-scaled
chart would make a still wrist look identical to a violent one. Values above the
top are clipped. History is 40 s, one bar per second.

Redraw cadence is adaptive: once a second while there is any activity in the
window, falling back to "only when something changed" (roughly once a minute) when
the wrist is still. The accelerometer dominates this app's power draw either way,
but there is no reason to spend CPU repainting an unchanged screen for hours.

## Controls

| Input | Action |
|---|---|
| **Select** (ENTER/START, or a tap on touch devices) | Toggle mute for 5 minutes |
| **Menu** | Vibration / Sound / Light / Phone alert toggles, plus Test and Setup link |
| **Back** | Exit, with a confirmation that times out after 10 s |

**Mute** is a temporary state, not a setting: it is there for "I am about to shake
my own wrist on purpose" (sport, a bumpy drive) and expires by itself after 5
minutes. While muted, detection keeps running - only the alerting is suppressed -
and the screen shows `MUTE` (or `MUTE!` if a detection fired while silenced), plus
the struck-through speaker icon.

All four alert channels are **opt-out**: on a fresh install they are already on. An
alarm app that starts up silent until someone finds the settings menu is worse than
useless. If you switch all four off, the status line reads `SILENT` and the row shows
the struck-through speaker - detection still runs, but nothing can be reported.

**Menu → Test** fires the whole alert path on demand, so it can be checked without
shaking anything. It calls the same `triggerAlarm()` a real detection calls, not a
private copy, and it deliberately respects mute and the Phone alert toggle - a test
that bypassed them would report success on a configuration that stays silent when it
matters. The screen reports the phone result (`sending` / `sent` / `failed <code>`),
which is the only part you cannot feel.

## The algorithm

Amplitude threshold-crossing counting over a sliding window - deliberately not
spectral/FFT analysis, which on Monkey C would cost far more CPU and RAM than it
is worth for what we are looking for. See
[ShakeDetector.mc](source/ShakeDetector.mc); it has no dependency on sensors, UI or
storage, which is what makes it unit-testable.

| Constant | Value | Meaning |
|---|---|---|
| `BASELINE_MG` | 1000 | magnitude of the acceleration vector at rest (1 g in milli-G) |
| `EXCURSION_THRESHOLD_MG` | 625 | deviation from that baseline which counts as an excursion |
| `WINDOW_SECONDS` | 5 | length of the sliding window |
| `CROSSING_ALARM_COUNT` | 8 | crossings within the window that mean "alarm" |
| `WARMUP_SECONDS` | 3 | seconds ignored after the sensor is enabled |
| `REPEAT_INTERVAL_SECONDS` | 5 | how often the alert repeats while shaking continues |

Once a second the app receives 25 samples per axis and, for each sample:

1. computes the magnitude `sqrt(x² + y² + z²)` in milli-G;
2. checks whether `|magnitude - 1000| > 625`;
3. counts a **rising edge** only - each excursion over the threshold, not every
   sample that is still above it. The "was above" flag deliberately survives
   across seconds, so an excursion straddling a second boundary is not counted
   twice.

The per-second count goes into a 5-slot ring buffer. When the sum over the window
reaches 8, the alarm fires **once** (on the rising edge); while the shaking
continues it repeats every 5 s rather than either chattering every second or going
silent until everything settles. When the window falls back below the threshold the
alarm resets and can fire again. Because the window is a *sum*, a brief pause does
not interrupt it - and equally, the total stays elevated for a few seconds after
the movement stops.

Tuning notes: raise `CROSSING_ALARM_COUNT` or `EXCURSION_THRESHOLD_MG` if you get
false alarms, lower them if real events are missed. The two interact - the threshold
decides what counts as an excursion at all, the count decides how many are needed -
and both are worth setting from recordings of your own nights rather than by
guesswork.

A minimum-duration requirement was tried here and removed: it is the most effective
thing available against false alarms without frequency analysis, since turning over
in bed takes 1-3 s while a clonic phase lasts 30 or more, but it makes the app
tiresome to test by hand and the simple version detects real shaking perfectly well.
If false alarms ever become the problem, that is the first thing to bring back.

### Known limits of this approach

- **The tonic phase is invisible.** Sustained muscle contraction produces almost no
  movement, so an amplitude-crossing counter cannot see it. Only the clonic phase
  is detectable this way.
- **No frequency selectivity.** The counter cannot tell rhythmic 4-8 Hz jerking
  from vigorous irregular movement; it only knows how often the amplitude got
  large. This is what the real OpenSeizureDetector uses an FFT for, and checking
  the regularity of the intervals between crossings would be the cheap way to
  approximate it. Not implemented.
- **Amplitude gets damped** by an arm pinned under bedding, which is the known
  weak spot of wrist accelerometry overnight and the reason clinical devices add a
  second modality. Heart rate was tried as that second modality and removed again -
  it needs sleeping-baseline tracking to be worth anything, and that needs data.
- Focal, absence and atonic seizures are out of scope entirely.

## Phone alert

A detection is also POSTed to the backend in [backend/](backend/), which pushes a
web notification to a phone subscribed through its setup page. **The phone is an
amplifier, never a dependency**: connection failures are deliberately silent, because
an alarm app that complains about its own connectivity all night gets switched off -
a worse failure than a missed push.

Setup, once per watch:

1. **Menu → Setup link** on the watch. It POSTs to `/api/shorten` and shows a
   six-character code.
2. Type `<host>/s/<code>` into a phone browser. That redirects to the setup page,
   where a button subscribes the browser to push.
3. Done. From then on every detection POSTs `{deviceId}` to `/api/alert`.

Notes on [ShakeDetectorPhone.mc](source/ShakeDetectorPhone.mc):

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

Why a server and web push rather than something simpler: the companion has to work
on iOS as well as Android. That rules out the usual trick of running a small HTTP
server on the phone and posting to it over the loopback address, because iOS
suspends background processes and will not keep a listening socket alive. Web push
is the one route that needs no native app on either platform - at the cost that it
is an ordinary notification, so it obeys silent mode and cannot repeat until
acknowledged. If waking someone through silent mode ever becomes a requirement, a
push service with an emergency priority (Pushover, ntfy) is the next step and needs
no watch-side change beyond the URL.

## Building

Needs Connect IQ SDK 6.4.2+ (developed against 9.2.0) and a developer key.

In VS Code with the Monkey C extension, use the checked-in **Run App** and **Run
Tests** configurations in the Run and Debug panel. Individual `(:test)` functions
also appear in the native Testing panel (the flask icon).

Two things that waste time otherwise:

- Test results are **not** in the Terminal panel, which only shows `BUILD
  SUCCESSFUL`. `PASS`/`FAIL` and the `RESULTS` summary go to the **Debug Console**
  (`Ctrl+Shift+Y`).
- A launcher-icon rescale warning per device whose icon size is not 70x70 used to be
  expected and ignorable (see below). On SDK 9.2.0 a per-device CLI build emits no
  warnings at all - neither that one nor `Invalid device id found in the application
  manifest` - so silence is not evidence that every id in the manifest is good.

### Device coverage

`manifest.xml` lists **124 devices**, and the list is generated rather than typed.
Every id is a filename in the SDK's own device reference
(`Sdks/<sdk>/doc/docs/Device_Reference/<id>.html`), filtered to wrist-worn devices
that declare the `Watch App` type and the `Background` type - the latter arrived in
Connect IQ 2.4 and so stands in for satisfying `minSdkVersion` below. That drops the
Edge/GPSMAP/Montana/Oregon/Rino/eTrex families, the watch-face-only fr45 and
garminswim2, and the pre-2.4 generation (fenix3, epix gen 1, vivoactive gen 1,
fr230/235/630/920xt, D2 Bravo). To extend the list, re-run that filter against a
newer SDK - do not add ids by hand.

`minSdkVersion` is kept at **2.4.0** for maximum installability, and that is a real
constraint rather than a formality, because `monkeyc` does not enforce it either - a
build with `minSdkVersion="1.2.0"` succeeds even though the code uses APIs from 2.4
and 3.0. Nothing stops the app installing on a watch too old for it and then
throwing at runtime, so the code stays inside what 2.4 offers:

- `Ui.Menu2`/`ToggleMenuItem` are API 3.0, so `onMenu()` checks `Ui has :Menu2` and
  falls back to the 1.x-era `Ui.Menu`, which has no toggle widget and spells the
  state out in the label (`Vibration: ON`).
- `SCREEN_SHAPE_SEMI_OCTAGON` only exists from the Instinct era, so it is read
  behind a `System has :` check - a device that lacks the constant cannot be
  Instinct-shaped anyway.
- Fonts are the plain `FONT_NUMBER_*`, not the newer `FONT_SYSTEM_NUMBER_*`
  aliases, and the icons use only lines, rectangles and circles - notably **not**
  `Dc.drawArc`. A missing method aborts the rest of `onUpdate()`, which silently
  erases everything drawn after the offending call rather than failing loudly.

The legacy menu path is written but untested: it needs a genuine CIQ 2.x device, and
the locally installed simulator is new enough to take the `Menu2` branch.

### Launcher icon

One image for every device: `resources/images/icon_70x70.png`, a dark glyph on white.
70x70 is the largest size any Connect IQ device asks for, so it is only ever scaled
*down*, which looks acceptable everywhere.

Every device that wants a different size therefore logs a rescale warning on build.
**That is accepted deliberately** - a per-device icon is not worth a directory per
device across a manifest this wide. If you ever do want a pixel-exact icon for one
device, a `resources-<device>/` directory whose `bitmaps.xml` redefines
`LauncherIcon` is picked up automatically by that naming convention; do not add it to
`monkey.jungle` by hand, which only produces a duplicate-resource-path warning.

One trap worth remembering: the background must not be transparent. The first version
of this icon was a black glyph on transparency, which was invisible in Instinct's
black app list - the icon was there, just unseeable.

## Layout of the source

| File | Responsibility |
|---|---|
| [ShakeDetector.mc](source/ShakeDetector.mc) | the algorithm, dependency-free and unit-tested |
| [ShakeDetectorTest.mc](source/ShakeDetectorTest.mc) | 8 `(:test)` cases; compiled in only with `--unit-test` |
| [ShakeDetectorSensors.mc](source/ShakeDetectorSensors.mc) | accelerometer subscription, alerting |
| [ShakeDetectorState.mc](source/ShakeDetectorState.mc) | screen mode, mute flag and its expiry timer |
| [ShakeDetectorPhone.mc](source/ShakeDetectorPhone.mc) | device id, and the two requests to the backend |
| [ShakeDetectorView.mc](source/ShakeDetectorView.mc) | main view, input delegate, menus, exit dialog |
| [ShakeDetectorLinkView.mc](source/ShakeDetectorLinkView.mc) | setup screen showing the short code |
| [ShakeDetectorTestView.mc](source/ShakeDetectorTestView.mc) | manual alarm test and its result |
| [ShakeDetectorLayout.mc](source/ShakeDetectorLayout.mc) | the whole screen: positioning, chart, pictograms |
| [ShakeDetectorApp.mc](source/ShakeDetectorApp.mc) | app entry point, 1 Hz tick |
| [ShakeDetectorCommon.mc](source/ShakeDetectorCommon.mc) | logging, settings keys and defaults |

Implementation notes worth knowing:

- **No copy of the sample window is kept.** The detector only ever needs one
  second at a time, so samples go straight from the sensor buffer into it.
- **Short sensor buffers are skipped, not zero-padded.** A zeroed sample looks
  like a 1000 mG excursion to the detector and would inject a phantom crossing.
- **The accelerometer is registered from `App.onStart()`**, not from the view's
  `onLayout()`, which can run more than once and would register a second listener.
- **`Attention.backlight()` is wrapped in try/catch** - it throws
  `BacklightOnTooLongException`, which would otherwise abort the alert before the
  vibration.
- **Sensors are released in three calls on exit**, including the undocumented
  `Sensor.enableSensorEvents(null)`, without which the watch keeps draining its
  battery after the app closes.
- **Settings are read from Storage at alarm time**, not cached at start-up, so a
  toggle applies to the very next alarm without a restart.
- **The phone POST is the last thing `triggerAlarm()` does**, after the wrist has
  already been buzzed. Nothing on the network may delay the local alert.

## Backend

Node + Express + SQLite in [backend/](backend/). Copy `.env.example` to `.env`,
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

Five things there are load-bearing and easy to undo by accident:

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
- **Accepted risks, consciously.** The id is generated on the watch with `Math.rand()`
  seeded from the clock, so its entropy is weaker than 32 hex characters suggest; and
  knowing an id is enough to subscribe a browser or post an alert. Both are tolerable while
  the id stays unpublished, and the fix if that ever changes is to split identity from
  authorisation: use `System.getDeviceSettings().uniqueIdentifier` (which exists, 40 hex
  characters, but is readable by any app and therefore not a secret) as the identity, drop
  the shared `secret` in favour of authorising unsubscribe by the browser's own push
  endpoint, and have the server issue the watch a token to send with each alert.
- **The debug endpoints `GET /api/devices` and `GET /api/logs` were deliberately
  removed**, and the reason is in a comment where each used to be. Listing device
  ids closed a takeover chain: the list gave an id, `/setup?device=<id>` returns
  that device's `secret`, and `DELETE /api/device/:id` accepts it. The access model
  now is "whoever has the link controls the device", which is only honest because
  the id is unguessable.

## Credit

This project was inspired by
[OpenSeizureDetector](https://github.com/OpenSeizureDetector/Garmin_sd), which does
the real, validated analysis on a phone and is worth looking at if that is what you
need. Everything here - the detector, the layout, the backend and the phone-side
protocol - is an independent implementation, written from scratch and sharing no
code with it.

## License

Copyright (C) 2026 Alex Goldobin

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the [GNU General Public License](LICENSE) for more
details.

GPLv3 is a deliberate choice, not an inherited obligation - the code is original
(see Credit above). It matches the license of the project that inspired this one,
which keeps the door open in that direction.
