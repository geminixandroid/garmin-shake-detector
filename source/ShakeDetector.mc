import Toybox.Lang;
import Toybox.Math;

// ShakeDetector - the whole detection algorithm, deliberately kept free of any
// dependency on sensors, UI or storage so it can be unit tested (see
// ShakeDetectorTest.mc).
//
// The algorithm counts amplitude threshold *crossings* in a sliding window
// rather than doing any spectral (FFT) analysis: on Monkey C that is far
// cheaper in CPU and memory, and it is a decent match for what we are looking
// for - obviously rhythmic, high-amplitude shaking of the wrist.
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

  // Ignore the first few seconds after the accelerometer is enabled - on some
  // devices the very first samples after registerSensorDataListener() are
  // unstable/noisy.
  const WARMUP_SECONDS as Number = 3;

  // While the alarm is active and the shaking hasn't stopped, repeat the signal
  // this often instead of staying silent until things go fully quiet.
  const REPEAT_INTERVAL_SECONDS as Number = 5;

  // Ring buffer: number of threshold crossings in each of the last
  // WINDOW_SECONDS seconds. One slot = one call to addSampleWindow(), which is
  // made once a second.
  var mCrossingsPerSecond as Array<Number> = new Array<Number>[WINDOW_SECONDS];
  var mBucketIndex as Number = 0;

  // Whether the previous sample was above the threshold. This deliberately
  // survives across calls, so a crossing straddling a second boundary is not
  // counted twice.
  var mWasAboveThreshold as Boolean = false;

  // The alarm has already been raised: don't let it chatter every second while
  // the shaking continues (see REPEAT_INTERVAL_SECONDS).
  var mAlarmActive as Boolean = false;

  var mSecondsSeen as Number = 0;
  var mSecondsSinceLastAlarm as Number = 0;

  // History of the window total - one entry per second, oldest first, newest
  // last - purely so the view can plot it. This is the actual decision variable
  // the alarm compares against CROSSING_ALARM_COUNT, so a chart of it with a
  // line at that threshold shows exactly how close things are to firing.
  const TRACE_LENGTH as Number = 40;
  var mTrace as Array<Number> = new Array<Number>[TRACE_LENGTH];

  function initialize() {
    for (var i = 0; i < WINDOW_SECONDS; i += 1) {
      mCrossingsPerSecond[i] = 0;
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
    var crossings = 0;
    for (var i = startIndex; i < startIndex + count; i += 1) {
      var xi = x[i].toFloat();
      var yi = y[i].toFloat();
      var zi = z[i].toFloat();
      var magnitude = Math.sqrt(xi * xi + yi * yi + zi * zi);
      var isAboveThreshold =
        (magnitude - BASELINE_MG).abs() > EXCURSION_THRESHOLD_MG;
      // Count rising edges only - each "excursion over the threshold", not
      // every individual sample that happens to still be above it.
      if (isAboveThreshold && !mWasAboveThreshold) {
        crossings += 1;
      }
      mWasAboveThreshold = isAboveThreshold;
    }

    if (crossings > 0) {
      writeLog("ShakeDetector", "crossings this second=" + crossings);
    }

    mSecondsSeen += 1;
    if (mSecondsSeen <= WARMUP_SECONDS) {
      // Still warming up - drop these crossings entirely rather than letting
      // start-up noise fill the window.
      return false;
    }

    mCrossingsPerSecond[mBucketIndex] = crossings;
    mBucketIndex = (mBucketIndex + 1) % WINDOW_SECONDS;

    var total = 0;
    for (var i = 0; i < WINDOW_SECONDS; i += 1) {
      total += mCrossingsPerSecond[i];
    }
    if (total > 0) {
      writeLog("ShakeDetector", "total crossings in window=" + total);
    }

    // Shift the trace along by one second. 40 copies once a second is nothing,
    // and it keeps the drawing code free of ring-buffer index arithmetic.
    for (var i = 0; i < TRACE_LENGTH - 1; i += 1) {
      mTrace[i] = mTrace[i + 1];
    }
    mTrace[TRACE_LENGTH - 1] = total;

    if (total >= CROSSING_ALARM_COUNT) {
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
