# Building, device coverage and Connect IQ traps

Needs Connect IQ SDK 6.4.2+ (developed against 9.2.0) and a developer key. A
prebuilt version is also on the
[Connect IQ Store](https://apps.garmin.com/apps/ba40a721-acb3-4298-95f3-efdc69d93969);
build your own to change the app or to point `SERVER_URL` at your own backend.

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

## Device coverage

`manifest.xml` lists **125 devices**. The one hardware requirement is
`Sensor.getMaxSampleRate() >= 25`.

**Incompatible devices:** approachs60, edge_1000, edge_520, edge_520plus, edge_530, edge_540, edge_550, edge_820, edge_830, edge_840, edge_850, edge_1030, edge_1030bontrager, edge_1030plus, edge_1040, edge_1050, edge_explore, edge_explore2, edge_mtb, edge_130, edge_130plus, etrex_touch, gpsmap_66, gpsmap_67, gpsmap_86, gpsmap_h1, montana_7xx, oregon_7xx, rino_7xx.

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

## One layout for every device

No app name anywhere, five things in the same order. Instinct-shaped watches
(semi-octagon display) have a small round sub-window in the top right corner, so
there the battery goes inside it, the clock shifts left to clear it, and the chart
starts lower down where the full width is free again. That is the entire difference
- three fractions in [ShakeDetectorLayout.mc](../source/ShakeDetectorLayout.mc), not
a second layout class.

## Launcher icon

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
| [ShakeDetector.mc](../source/ShakeDetector.mc) | the algorithm, dependency-free and unit-tested |
| [ShakeDetectorTest.mc](../source/ShakeDetectorTest.mc) | 12 `(:test)` cases; compiled in only with `--unit-test` |
| [ShakeDetectorSensors.mc](../source/ShakeDetectorSensors.mc) | accelerometer subscription, alerting |
| [ShakeDetectorState.mc](../source/ShakeDetectorState.mc) | screen mode, mute flag and its expiry timer |
| [ShakeDetectorPhone.mc](../source/ShakeDetectorPhone.mc) | device id, and the two requests to the backend |
| [ShakeDetectorView.mc](../source/ShakeDetectorView.mc) | main view, input delegate, menus, exit dialog |
| [ShakeDetectorLinkView.mc](../source/ShakeDetectorLinkView.mc) | setup screen showing the short code |
| [ShakeDetectorTestView.mc](../source/ShakeDetectorTestView.mc) | manual alarm test and its result |
| [ShakeDetectorLayout.mc](../source/ShakeDetectorLayout.mc) | the whole screen: positioning, chart, pictograms |
| [ShakeDetectorApp.mc](../source/ShakeDetectorApp.mc) | app entry point, 1 Hz tick |
| [ShakeDetectorCommon.mc](../source/ShakeDetectorCommon.mc) | logging, settings keys and defaults |

## Implementation notes worth knowing

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
