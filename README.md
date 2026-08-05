# ShakeDetector

A Garmin Connect IQ watch app that detects sustained, high-amplitude wrist shaking
using the accelerometer. Alerts with vibration, sound and backlight, with optional
phone push notifications.

**[Install from the Connect IQ Store](https://apps.garmin.com/en-US/apps/ba40a721-acb3-4298-95f3-efdc69d93969)**

**Detection runs entirely on the watch** - no phone, no network, nothing to pair.
A phone can optionally be notified as well, purely as a louder speaker; if it is
absent the watch behaves exactly the same.

Two equally supported ways to run it, differing only in whose server the optional
phone alerts go through:

- **The store build** (link above). Phone alerts go through the live instance at
  <https://shakedetector.geminixandroid.com/>, whose landing page explains the setup
  flow to a wearer. Nothing to configure.
- **Build it yourself.** This repository holds both halves - the watch app in
  [source/](source/) and the server in [backend/](backend/). Point `SERVER_URL` in
  [ShakeDetectorPhone.mc](source/ShakeDetectorPhone.mc) at your own host, build, and
  no data leaves your infrastructure. `SERVER_URL` is a build-time constant, which is
  why this needs a build of your own rather than a setting.

Either way the detection itself is local to the watch and identical.

> **This is a personal, experimental project. It is NOT a medical device and has
> not been clinically validated.** The algorithm is a crude amplitude-threshold
> counter, not a validated seizure detector. Do not rely on it to detect a
> seizure or any other medical event, and do not treat it as a substitute for
> medical supervision.

## What it looks like

One layout for every device - no app name anywhere, five things in the same order:

<img width="640" src="https://github.com/user-attachments/assets/28bd4bd8-ee52-4d4d-baee-a36d17606177" />

The bars are not raw acceleration: they are the decision variable the alarm compares
against its threshold, and the dashed line is that threshold. Details, including why
bars above the line do not always mean an alarm, are in
[docs/algorithm.md](docs/algorithm.md#the-chart-on-the-watch).

## Controls

| Input | Action |
|---|---|
| **Select** (ENTER/START, or a tap on touch devices) | Toggle mute for 5 minutes |
| **Menu** | Vibration / Sound / Light / Phone alert toggles, plus Test and Setup link |
| **Back** | Exit, with a confirmation that times out after 10 s |

**Mute** is a temporary state, not a setting: it is there for "I am about to shake
my own wrist on purpose" (sport, a bumpy drive) and expires by itself after 5
minutes. While muted, detection keeps running - only the alerting is suppressed -
and the screen shows `MUTE` (or `MUTE!` if a detection fired while silenced).

All four alert channels are **opt-out**: on a fresh install they are already on. An
alarm app that starts up silent until someone finds the settings menu is worse than
useless. If you switch all four off, the status line reads `SILENT` - detection still
runs, but nothing can be reported.

**Menu → Test** fires the whole alert path on demand, so it can be checked without
shaking anything. It calls the same `triggerAlarm()` a real detection calls, not a
private copy, and it deliberately respects mute and the Phone alert toggle - a test
that bypassed them would report success on a configuration that stays silent when it
matters.

## How it works

Once a second the accelerometer delivers 25 samples per axis. The detector computes
the magnitude of each, counts how often it crosses a fixed excursion threshold, and
raises the alarm when **two** conditions hold at once:

- **Intensity** - enough crossings inside a 5 s sliding window.
- **Duration** - an unbroken run of half-second slots that each carried activity,
  currently 6 of them, so the alarm fires 3.0-3.5 s after the shaking starts.

Both are needed. A single hard knock against a bed frame reaches the intensity
threshold inside one second, and a window total on its own cannot tell that from
three seconds of shaking. There is no frequency analysis, for reasons that turn out
to be about the sample rate rather than about CPU.

The full description, the constants and how to tune them, the reasoning about
frequency filtering, and the known limits of the approach:
**[docs/algorithm.md](docs/algorithm.md)**.

## Phone alert

Optional, and never a dependency - the watch alerts the same way with or without it.
Setup, once per watch:

1. **Menu → Setup link** on the watch shows a six-character code.
2. Type `<host>/s/<code>` into a phone browser and press Subscribe on the page it
   opens. On iOS, add the page to the Home Screen first and open it from there -
   Safari tabs cannot receive web push.
3. Done. Several phones per watch are supported: open the same link on each.

Watch-side request handling and the whole backend are in
**[docs/phone-alert.md](docs/phone-alert.md)**.

## Building

Needs Connect IQ SDK 6.4.2+ (developed against 9.2.0) and a developer key. In VS
Code with the Monkey C extension, use the checked-in **Run App** and **Run Tests**
configurations. `manifest.xml` lists 125 devices; the one hardware requirement is
`Sensor.getMaxSampleRate() >= 25`.

Device coverage, the `minSdkVersion` constraints, the launcher-icon rules and the
Connect IQ traps that cost the most time: **[docs/connect-iq.md](docs/connect-iq.md)**.

## Documentation

| Document | Contents |
|---|---|
| [docs/algorithm.md](docs/algorithm.md) | the detector, its constants, tuning, why there is no frequency filter, known limits, the chart |
| [docs/connect-iq.md](docs/connect-iq.md) | building, device coverage, API-level constraints, launcher icon, source layout, platform traps |
| [docs/phone-alert.md](docs/phone-alert.md) | why web push, the watch-side request rules, the backend and its access model |

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
