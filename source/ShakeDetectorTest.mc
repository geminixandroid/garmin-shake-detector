using Toybox.Test;
import Toybox.Lang;

const SAMPLES_PER_SECOND = 25;

// One "second" of samples (n of them) containing exactly nCrossings rising
// edges: baseline, brief excursion, baseline, ... Each excursion is a single
// sample surrounded by baseline ones, so it is one rising edge, not a run.
function buildWindowWithCrossings(nCrossings as Number, n as Number) as
  [Array<Number>, Array<Number>, Array<Number>] {
  var x = new Array<Number>[n];
  var y = new Array<Number>[n];
  var z = new Array<Number>[n];
  for (var i = 0; i < n; i += 1) {
    x[i] = 1000; // baseline: 1 g on x, nothing on y/z
    y[i] = 0;
    z[i] = 0;
  }
  for (var k = 0; k < nCrossings; k += 1) {
    // |5000 - 1000| = 4000, well over EXCURSION_THRESHOLD_MG
    x[k * 2 + 1] = 5000;
  }
  return [x, y, z];
}

// The detector ignores its first WARMUP_SECONDS calls, so any test about window
// accumulation has to get past that first.
function primeWarmup(detector as ShakeDetector) as Void {
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);
  for (var i = 0; i < detector.WARMUP_SECONDS; i += 1) {
    detector.addSampleWindow(quiet[0], quiet[1], quiet[2], 0, SAMPLES_PER_SECOND);
  }
}

//! Feed the same second of samples `seconds` times. Returns the 1-based index of
//! the second the detector first fired on, or 0 if it never did.
function feed(
  detector as ShakeDetector,
  window as [Array<Number>, Array<Number>, Array<Number>],
  seconds as Number
) as Number {
  var firstTrigger = 0;
  for (var i = 1; i <= seconds; i += 1) {
    var triggered = detector.addSampleWindow(
      window[0],
      window[1],
      window[2],
      0,
      SAMPLES_PER_SECOND
    );
    if (triggered && firstTrigger == 0) {
      firstTrigger = i;
    }
  }
  return firstTrigger;
}

(:test)
function testIgnoresWarmupPeriod(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  var burst = buildWindowWithCrossings(8, SAMPLES_PER_SECOND);
  // Even a huge burst during warm-up is ignored - it may just be start-up noise.
  for (var i = 0; i < detector.WARMUP_SECONDS; i += 1) {
    var triggered = detector.addSampleWindow(
      burst[0],
      burst[1],
      burst[2],
      0,
      SAMPLES_PER_SECOND
    );
    Test.assertEqualMessage(
      triggered,
      false,
      "Bursts during the warm-up period should be ignored"
    );
  }
  return true;
}

(:test)
function testNoAlarmWhenStationary(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);
  Test.assertEqualMessage(
    feed(detector, quiet, 30),
    0,
    "A stationary signal should never trigger the alarm"
  );
  return true;
}

//! Crossings accumulate across seconds: 3 per second reaches the count of 8 on
//! the third second (3 + 3 + 3 = 9) and not before.
(:test)
function testAccumulatesAcrossWindowsAndTriggers(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var window = buildWindowWithCrossings(3, SAMPLES_PER_SECOND);
  Test.assertEqualMessage(
    feed(detector, window, 5),
    3,
    "Should trigger on the second the cumulative crossings reach the alarm count"
  );
  return true;
}

//! A signal that never gets the window total to CROSSING_ALARM_COUNT never
//! alarms, however long it goes on for.
(:test)
function testWeakSignalNeverAlarmsHoweverLong(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  // 1 crossing/s over a 5 s window = 5, under CROSSING_ALARM_COUNT of 8.
  var weak = buildWindowWithCrossings(1, SAMPLES_PER_SECOND);
  Test.assertEqualMessage(
    feed(detector, weak, 60),
    0,
    "A signal below the alarm count must never alarm"
  );
  return true;
}

(:test)
function testDoesNotRetriggerEverySecond(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var burst = buildWindowWithCrossings(8, SAMPLES_PER_SECOND);

  Test.assertEqualMessage(
    feed(detector, burst, 1),
    1,
    "8 crossings in one second should trigger immediately"
  );
  Test.assertEqualMessage(
    detector.addSampleWindow(burst[0], burst[1], burst[2], 0, SAMPLES_PER_SECOND),
    false,
    "Should not re-trigger every second while the shaking continues"
  );
  return true;
}

(:test)
function testRepeatsPeriodicallyWhileStillActive(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var burst = buildWindowWithCrossings(8, SAMPLES_PER_SECOND);
  feed(detector, burst, 1); // first alarm

  // Silent until REPEAT_INTERVAL_SECONDS have passed, then fires again.
  for (var i = 0; i < detector.REPEAT_INTERVAL_SECONDS - 1; i += 1) {
    Test.assertEqualMessage(
      detector.addSampleWindow(burst[0], burst[1], burst[2], 0, SAMPLES_PER_SECOND),
      false,
      "Should stay quiet before the repeat interval elapses"
    );
  }
  Test.assertEqualMessage(
    detector.addSampleWindow(burst[0], burst[1], burst[2], 0, SAMPLES_PER_SECOND),
    true,
    "Should re-fire once the repeat interval has elapsed"
  );
  return true;
}

(:test)
function testAlarmsAgainAfterActivityDiesDown(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var burst = buildWindowWithCrossings(8, SAMPLES_PER_SECOND);
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);

  Test.assertEqualMessage(feed(detector, burst, 1), 1, "First burst should alarm");
  // Long enough for the burst to age fully out of the sliding window.
  feed(detector, quiet, detector.WINDOW_SECONDS);
  Test.assertEqualMessage(
    feed(detector, burst, 1),
    1,
    "Should be able to alarm again once activity has died down"
  );
  return true;
}

//! Crossings outside the window must not combine with new ones: two separate
//! bursts of 5, a whole window apart, are not an alarm even though 5 + 5 > 8.
(:test)
function testAgesOutCrossingsOutsideWindow(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var partial = buildWindowWithCrossings(5, SAMPLES_PER_SECOND);
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);

  Test.assertEqualMessage(
    feed(detector, partial, 1),
    0,
    "5 crossings alone should not trigger"
  );
  feed(detector, quiet, detector.WINDOW_SECONDS);
  Test.assertEqualMessage(
    feed(detector, partial, 1),
    0,
    "Aged-out crossings should not count towards a new alarm"
  );
  return true;
}
