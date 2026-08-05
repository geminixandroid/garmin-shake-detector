import Toybox.Lang;
import Toybox.Math;

// ShakeDetector - the whole detection algorithm, deliberately kept free of any
// dependency on sensors, UI or storage so it can be unit tested (see
// ShakeDetectorTest.mc).
//
// The algorithm counts amplitude threshold *crossings* in a sliding window, with
// no frequency analysis at all. That is not a CPU decision - a band-pass IIR
// would cost four multiply-adds per sample. It is the sample rate: at 25 Hz
// Nyquist is 12.5 Hz, which leaves no room above a 3-8 Hz band for a filter to
// roll off in, and impulse energy above it aliases straight into that band. See
// "Why there is no frequency filter" in docs/algorithm.md.
//
// The consequence to keep in mind while reading the rest: this code knows how
// often the amplitude got large, and never how rhythmically.
//
// The alarm needs two things at once - enough crossings in the window
// (CROSSING_ALARM_COUNT) AND an unbroken run of active slots
// (SUSTAINED_SLOTS). The count says "violent", the run says "still going";
// only together do they mean shaking rather than a single swing of the arm.
//
// The run is a separate counter and not a property of the window on purpose.
// The window is a sum, so it forgives gaps by design - two brief bursts a few
// seconds apart add up in it exactly like continuous movement. The run counter
// is reset outright by the first quiet slot, and that is what makes the
// duration requirement mean anything.
//
// The samples arrive from the sensor once a second, but the run is measured in
// SLOTS_PER_SECOND sub-slices of that second. Resolution is what a duration
// test costs: a run of N slots only guarantees more than N-1 slots of real
// movement, because the slices are aligned to the sensor callback rather than
// to the wrist. At one slot per second that slop is a whole second, so
// demanding "more than 3 s" meant waiting 4 to 5 s. Halving the slot halves the
// slop, and the same guarantee now fires a second and a half sooner.
//
// NOT a medical device and not clinically validated - see README.
class ShakeDetector {
  // Magnitude of the acceleration vector at rest, in milli-G (the sensor
  // reports milli-G, so 1 g at rest = 1000).
  const BASELINE_MG as Number = 1000;
  // Deviation from that baseline which counts as an amplitude "excursion".
  const EXCURSION_THRESHOLD_MG as Number = 625;

  // How many of the last seconds the sliding window covers, and how many
  // crossings within it count as an alarm.
  const WINDOW_SECONDS as Number = 5;
  const CROSSING_ALARM_COUNT as Number = 8;

  // How finely each second of samples is sliced for the duration test. Two
  // gives half-second slots, which is as far as it is worth going: below that a
  // slot holds too few samples to tell a rhythm from a single excursion.
  const SLOTS_PER_SECOND as Number = 2;
  const WINDOW_SLOTS as Number = WINDOW_SECONDS * SLOTS_PER_SECOND;

  // The count alone is not enough: at 25 Hz a single sharp swing or a knock
  // against a table can put CROSSING_ALARM_COUNT rising edges into one second,
  // and the window total would hit the threshold instantly. Shaking is defined
  // by lasting, so the alarm also needs a run of consecutive slots that each
  // carry activity of their own.
  //
  // A slot only joins the run if it holds at least this many crossings by
  // itself. One stray excursion is not a rhythm, and letting it extend a run
  // would make SUSTAINED_SLOTS meaningless. At half-second slots, 1 here is the
  // same rate as CROSSING_ALARM_COUNT over WINDOW_SECONDS asks for, so the two
  // gates stay consistent.
  const MIN_CROSSINGS_PER_SLOT as Number = 1;
  // How many such slots have to follow each other without a break. 6 half-second
  // slots is 3.0 s of slots, which means the alarm fires 3.0-3.5 s after the
  // shaking starts and never on less than 2.5 s of real movement.
  const SUSTAINED_SLOTS as Number = 6;

  // Ignore the first few seconds after the accelerometer is enabled - on some
  // devices the very first samples after registerSensorDataListener() are
  // unstable/noisy.
  const WARMUP_SECONDS as Number = 3;

  // While the alarm is active and the shaking hasn't stopped, repeat the signal
  // this often instead of staying silent until things go fully quiet.
  const REPEAT_INTERVAL_SECONDS as Number = 5;

  // Ring buffer: number of threshold crossings in each of the last WINDOW_SLOTS
  // slots. One call to addSampleWindow() fills SLOTS_PER_SECOND of them.
  var mCrossingsPerSlot as Array<Number> = new Array<Number>[WINDOW_SLOTS];
  var mSlotIndex as Number = 0;

  // Whether the previous sample was above the threshold. This deliberately
  // survives across calls, so a crossing straddling a second boundary is not
  // counted twice.
  var mWasAboveThreshold as Boolean = false;

  // The alarm has already been raised: don't let it chatter every second while
  // the shaking continues (see REPEAT_INTERVAL_SECONDS).
  var mAlarmActive as Boolean = false;

  var mSecondsSeen as Number = 0;
  var mSecondsSinceLastAlarm as Number = 0;

  // Length of the current unbroken run of slots carrying at least
  // MIN_CROSSINGS_PER_SLOT crossings. Reset to zero by the first slot that does
  // not, which is what makes two short bursts fail to add up: the window total
  // forgives a pause, this deliberately does not.
  var mConsecutiveActiveSlots as Number = 0;

  // History of the window total - one entry per second, oldest first, newest
  // last - purely so the view can plot it. This is the actual decision variable
  // the alarm compares against CROSSING_ALARM_COUNT, so a chart of it with a
  // line at that threshold shows exactly how close things are to firing.
  const TRACE_LENGTH as Number = 40;
  var mTrace as Array<Number> = new Array<Number>[TRACE_LENGTH];

  function initialize() {
    for (var i = 0; i < WINDOW_SLOTS; i += 1) {
      mCrossingsPerSlot[i] = 0;
    }
    for (var i = 0; i < TRACE_LENGTH; i += 1) {
      mTrace[i] = 0;
    }
  }

  function getTrace() as Array<Number> {
    return mTrace;
  }

  // True while the sliding window is over the alarm threshold. Used by the view
  // for the status line, so the ALARM indication clears itself once the shaking
  // stops instead of needing a separate timer.
  function isAlarmActive() as Boolean {
    return mAlarmActive;
  }

  // Processes one second of samples - the slice [startIndex, startIndex+count)
  // of the x/y/z buffers, in milli-G, without copying anything.
  //
  // Returns true exactly once when the alarm should fire (on the rising edge),
  // and again every REPEAT_INTERVAL_SECONDS while the shaking continues.
  function addSampleWindow(
    x as Array<Number>,
    y as Array<Number>,
    z as Array<Number>,
    startIndex as Number,
    count as Number
  ) as Boolean {
    // Warm-up is still decided per callback, so this has to run before the
    // per-slot work: the crossings are dropped entirely rather than allowed to
    // fill the window with start-up noise. mWasAboveThreshold is left to the
    // loop below either way, so the very first real slot starts from the true
    // state of the signal rather than from a stale flag.
    mSecondsSeen += 1;
    var warmingUp = mSecondsSeen <= WARMUP_SECONDS;

    var total = 0;
    for (var slot = 0; slot < SLOTS_PER_SECOND; slot += 1) {
      // Integer division on both ends, so the slices tile the second exactly
      // even when count does not divide evenly (25 samples -> 12 + 13).
      var from = startIndex + (slot * count) / SLOTS_PER_SECOND;
      var to = startIndex + ((slot + 1) * count) / SLOTS_PER_SECOND;

      var crossings = 0;
      for (var i = from; i < to; i += 1) {
        var xi = x[i].toFloat();
        var yi = y[i].toFloat();
        var zi = z[i].toFloat();
        var magnitude = Math.sqrt(xi * xi + yi * yi + zi * zi);
        var isAboveThreshold =
          (magnitude - BASELINE_MG).abs() > EXCURSION_THRESHOLD_MG;
        // Count rising edges only - each "excursion over the threshold", not
        // every individual sample that happens to still be above it. The flag
        // survives across slots and across calls, so an excursion straddling a
        // boundary is not counted twice.
        if (isAboveThreshold && !mWasAboveThreshold) {
          crossings += 1;
        }
        mWasAboveThreshold = isAboveThreshold;
      }

      if (warmingUp) {
        continue;
      }

      mCrossingsPerSlot[mSlotIndex] = crossings;
      mSlotIndex = (mSlotIndex + 1) % WINDOW_SLOTS;

      // Extend or break the run as each slot lands: a single quiet slot ends it
      // outright, so the counter really does measure uninterrupted shaking.
      if (crossings >= MIN_CROSSINGS_PER_SLOT) {
        mConsecutiveActiveSlots += 1;
      } else {
        mConsecutiveActiveSlots = 0;
      }
    }

    if (warmingUp) {
      return false;
    }

    for (var i = 0; i < WINDOW_SLOTS; i += 1) {
      total += mCrossingsPerSlot[i];
    }
    if (total > 0) {
      writeLog(
        "ShakeDetector",
        "total=" + total + " run=" + mConsecutiveActiveSlots + "/" + SUSTAINED_SLOTS
      );
    }

    // Shift the trace along by one second. 40 copies once a second is nothing,
    // and it keeps the drawing code free of ring-buffer index arithmetic.
    for (var i = 0; i < TRACE_LENGTH - 1; i += 1) {
      mTrace[i] = mTrace[i + 1];
    }
    mTrace[TRACE_LENGTH - 1] = total;

    // Decided once per callback rather than per slot: the sensor only wakes us
    // once a second anyway, and evaluating twice would halve REPEAT_INTERVAL.
    if (
      total >= CROSSING_ALARM_COUNT &&
      mConsecutiveActiveSlots >= SUSTAINED_SLOTS
    ) {
      if (!mAlarmActive) {
        mAlarmActive = true;
        mSecondsSinceLastAlarm = 0;
        return true;
      }
      // Already alarming and it hasn't stopped - repeat at a fixed interval
      // rather than going quiet until everything settles.
      mSecondsSinceLastAlarm += 1;
      if (mSecondsSinceLastAlarm >= REPEAT_INTERVAL_SECONDS) {
        mSecondsSinceLastAlarm = 0;
        return true;
      }
      return false;
    }

    // The window is quiet again - allow a future alarm to fire.
    mAlarmActive = false;
    mSecondsSinceLastAlarm = 0;
    return false;
  }
}
