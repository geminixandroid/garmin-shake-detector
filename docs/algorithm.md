# The algorithm

Amplitude threshold-crossing counting over a sliding window - no frequency analysis
of any kind, for reasons that are about the sample rate rather than about CPU (see
[Why there is no frequency filter](#why-there-is-no-frequency-filter) below). See
[ShakeDetector.mc](../source/ShakeDetector.mc); it has no dependency on sensors, UI
or storage, which is what makes it unit-testable.

| Constant | Value | Meaning |
|---|---|---|
| `BASELINE_MG` | 1000 | magnitude of the acceleration vector at rest (1 g in milli-G) |
| `EXCURSION_THRESHOLD_MG` | 625 | deviation from that baseline which counts as an excursion |
| `WINDOW_SECONDS` | 5 | length of the sliding window |
| `CROSSING_ALARM_COUNT` | 8 | crossings within the window that mean "alarm" |
| `SLOTS_PER_SECOND` | 2 | sub-slices each second is cut into for the duration test |
| `MIN_CROSSINGS_PER_SLOT` | 1 | crossings a single slot needs to count as "active" |
| `SUSTAINED_SLOTS` | 6 | consecutive active slots the alarm needs (3.0 s) |
| `WARMUP_SECONDS` | 3 | seconds ignored after the sensor is enabled |
| `REPEAT_INTERVAL_SECONDS` | 5 | how often the alert repeats while shaking continues |
| `SAMPLE_FREQUENCY` | 25 | Hz, in [ShakeDetectorSensors.mc](../source/ShakeDetectorSensors.mc) - a device-coverage floor, and the reason for the section below |

Once a second the app receives 25 samples per axis and, for each sample:

1. computes the magnitude `sqrt(x² + y² + z²)` in milli-G;
2. checks whether `|magnitude - 1000| > 625`;
3. counts a **rising edge** only - each excursion over the threshold, not every
   sample that is still above it. The "was above" flag deliberately survives
   across slot and callback boundaries alike, so an excursion straddling one is
   not counted twice.

The samples arrive once a second, but the detector cuts each callback into
`SLOTS_PER_SECOND` half-second slots and counts crossings per slot. Those go into a
10-slot ring buffer covering the 5 s window, and the alarm needs **two** conditions
at once:

- **Intensity** - the sum over the whole 5 s window reaches `CROSSING_ALARM_COUNT`.
- **Duration** - `SUSTAINED_SLOTS` slots *in a row* have each carried at least
  `MIN_CROSSINGS_PER_SLOT` crossings.

Intensity alone is not enough: at 25 Hz a single violent swing or a knock against a
table puts 8 rising edges into one second and hits the threshold instantly. And the
duration test has to be a **separate run counter**, not a count of non-empty slots
in the window, because the window is a sum and forgives gaps by design - two brief
bursts three seconds apart add up in it exactly like continuous movement. The run
counter is reset outright by the first slot that goes quiet.

Slot size is what a duration test costs. Slots are aligned to the sensor callback,
not to your wrist, so a run of N slots only guarantees a bit more than N-1 slots of
real movement. At one slot per second that slop is a whole second: insisting on
"more than 3 s" meant waiting 4 to 5 s before the watch buzzed. Half-second slots
halve the slop, so 6 slots fire **3.0-3.5 s** after the shaking starts and never on
less than 2.5 s of it. Going finer than half a second is not worth it - a slot
would hold too few samples to tell a rhythm from a single excursion.

When both conditions hold the alarm fires **once** (on the rising edge); while the
shaking continues it repeats every 5 s rather than either chattering every second
or going silent until everything settles. The decision itself is made once per
callback, not per slot, since that is as often as the sensor wakes the app. When
either condition lapses the alarm resets and can fire again.

## Tuning

Raise `CROSSING_ALARM_COUNT` or `EXCURSION_THRESHOLD_MG` if you get false alarms,
lower them if real events are missed. `SUSTAINED_SLOTS` is the "how long must it
last" knob - it is the one to change, in steps of `SLOTS_PER_SECOND` per second of
shaking, and 1 gives the old intensity-only behaviour. `MIN_CROSSINGS_PER_SLOT`
decides how easily a run survives a weak slot: raise it to demand vigorous shaking
throughout, at the cost of runs breaking on the turnaround between strokes. All are
worth setting from recordings of your own nights rather than by guesswork.

The minimum-duration requirement is the most effective thing available against
false alarms without frequency analysis: turning over in bed takes 1-3 s, while a
clonic phase lasts 30 or more. It was tried, removed as tiresome to test by hand,
and brought back once it became clear what the count-only version actually accepts
- a single hard knock against a bed frame reaches 8 crossings inside one second.
The cost is real, though: 3 s of deliberate shaking to test the thing by hand feels
much longer than it sounds, and **Menu → Test** exists partly for that reason.

## Why there is no frequency filter

Rhythmic 3-8 Hz jerking is what a clonic phase looks like in the frequency domain,
and separating it from vigorous irregular movement is exactly what this detector
cannot do. It is worth being precise about why, because the obvious reading -
"an FFT is too expensive on a watch" - is not the real obstacle.

**A frequency filter is not an FFT, and it is cheap.** Two one-pole IIRs, four
multiply-adds per sample, no buffer at all:

```monkey-c
mSlow += ALPHA_SLOW * (magnitude - mSlow);   // everything below the band
mFast += ALPHA_FAST * (magnitude - mFast);   // everything below the top of it
var band = mFast - mSlow;                    // band-passed signal
```

Even a 32-point FFT once a second is on the order of 80 butterflies, which is not a
catastrophe in an interpreter. Cost is not what rules this out.

**`SAMPLE_FREQUENCY` is.** At 25 Hz the Nyquist limit is 12.5 Hz, which leaves no
room above the band for a filter to roll off in. For `alpha = 1 - exp(-2*PI*fc/fs)`:

| Band edge | fc | alpha at fs=25 | Effect |
|---|---|---|---|
| Lower | 3 Hz | 0.53 | works |
| Upper | 10 Hz | 0.92 | very nearly a pass-through |

So the lower edge is enforceable and the upper edge is not: 5 Hz and 11 Hz cannot be
told apart. Worse, a knock against a bed frame is a broadband impulse whose energy
sits well above 12.5 Hz, and that energy **aliases straight into the band of
interest**. No digital filter can undo that - the folding happened in the ADC.

25 Hz is a device-coverage floor, not a signal-processing choice: it is the lowest
`Sensor.getMaxSampleRate()` among the devices in the manifest. Many watches report
50 (the simulator logs `maxSampleRate = 50` for fenix7), and at 50 Hz both band
edges become real. Sampling at `min(50, getMaxSampleRate())` is therefore the
prerequisite for any of this, at the cost of battery on the app's dominant consumer
and a code path that behaves differently per device.

**Magnitude is a poor input for a spectrum anyway.** `sqrt(x^2+y^2+z^2)` is
nonlinear: one back-and-forth stroke at 4 Hz produces *two* magnitude excursions, so
the fundamental lands at 8 Hz, with harmonics from the nonlinearity on top. The band
of interest moves up and smears out precisely where 25 Hz has no resolution left.
Filtering each axis separately and taking the magnitude of the filtered signal is
the correct order, at three times the state and arithmetic.

**And there would be nothing to set it from.** Which band, at what energy threshold?
Answering that needs labelled recordings of real events. Without them a frequency
filter is a knob that cannot be calibrated - worse than its absence, because it
creates the appearance of selectivity. This is the same reason heart rate was tried
as a second modality and removed.

The cheap thing that works at 25 Hz and is **not** implemented: **regularity of the
intervals between crossings**. The detector currently records only how many rising
edges occurred, not when. Keeping the sample index of each one makes the intervals
available, and rhythm shows up as a tight cluster of them while a single knock
produces one crossing and thrashing produces scatter. That measures period in the
time domain, so Nyquist does not apply, and it costs a few dozen integer operations
per second. It is frequency selectivity without frequency analysis, and it is the
first thing to add.

## Known limits of this approach

- **The tonic phase is invisible.** Sustained muscle contraction produces almost no
  movement, so an amplitude-crossing counter cannot see it. Only the clonic phase
  is detectable this way.
- **No frequency selectivity.** The counter only knows how often the amplitude got
  large, never how rhythmically - see the section above for why, and for what could
  be done about it without raising the sample rate.
- **Amplitude gets damped** by an arm pinned under bedding, which is the known
  weak spot of wrist accelerometry overnight and the reason clinical devices add a
  second modality.
- Focal, absence and atonic seizures are out of scope entirely.

## The chart on the watch

The bars are not raw acceleration - they are the **window total**, i.e. the exact
number the alarm compares against `CROSSING_ALARM_COUNT`, and the dashed line is
that threshold. So the chart shows a decision variable approaching its decision
line, which is what makes the tuning notes above actionable: if the bars regularly
brush the line while you are just walking, raise the threshold.

It shows the *intensity* half of the decision only. Bars over the line with no
alarm is the normal, correct look of a movement that was loud but too short - the
duration half is the run counter, which is not plotted. It goes to the log
(`total=24 run=4/6`) rather than onto a 40-bar chart that has no room for a second
series.

The y axis is fixed at twice the threshold and never auto-scales - an auto-scaled
chart would make a still wrist look identical to a violent one. Values above the
top are clipped. History is 40 s, one bar per second.

Redraw cadence is adaptive: once a second while there is any activity in the
window, falling back to "only when something changed" (roughly once a minute) when
the wrist is still. The accelerometer dominates this app's power draw either way,
but there is no reason to spend CPU repainting an unchanged screen for hours.
