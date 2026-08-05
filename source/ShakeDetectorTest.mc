using Toybox.Test;
import Toybox.Lang;

const SAMPLES_PER_SECOND = 25;

// One "second" of samples (n of them) containing exactly nCrossings rising
// edges: baseline, brief excursion, baseline, ... Each excursion is a single
// sample surrounded by baseline ones, so it is one rising edge, not a run.
//
// The excursions are spread evenly over the whole second rather than packed at
// the front, because the detector slices the second into slots and a helper
// that filled only the first slot would be testing a signal nobody's wrist
// produces. buildBurstInFirstSlot() below exists for when that IS the point.
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
    // +1 keeps a baseline sample ahead of every excursion, so each really is a
    // rising edge, and keeps the last sample of the second at baseline, so an
    // excursion never straddles into the next one.
    // |5000 - 1000| = 4000, well over EXCURSION_THRESHOLD_MG
    x[(k * n) / nCrossings + 1] = 5000;
  }
  return [x, y, z];
}

//! One "second" whose crossings all fall inside the first slot, leaving the
//! rest of the second at baseline.
function buildBurstInFirstSlot(nCrossings as Number, n as Number) as
  [Array<Number>, Array<Number>, Array<Number>] {
  var x = new Array<Number>[n];
  var y = new Array<Number>[n];
  var z = new Array<Number>[n];
  for (var i = 0; i < n; i += 1) {
    x[i] = 1000;
    y[i] = 0;
    z[i] = 0;
  }
  for (var k = 0; k < nCrossings; k += 1) {
    x[k * 2 + 1] = 5000;
  }
  return [x, y, z];
}

//! Whole seconds of continuous shaking the detector needs before it fires.
//! Derived rather than hard-coded so that changing the slot size does not turn
//! every expectation below into a puzzle.
function sustainedSeconds(detector as ShakeDetector) as Number {
  return detector.SUSTAINED_SLOTS / detector.SLOTS_PER_SECOND;
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

//! Both conditions have to be met - the count on its own is not enough, and
//! neither is the run.
(:test)
function testAccumulatesAcrossWindowsAndTriggers(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var window = buildWindowWithCrossings(3, SAMPLES_PER_SECOND);
  Test.assertEqualMessage(
    feed(detector, window, 6),
    sustainedSeconds(detector),
    "Should trigger on the second both the count and the run are satisfied"
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
    feed(detector, burst, sustainedSeconds(detector)),
    sustainedSeconds(detector),
    "Should trigger once the shaking has lasted SUSTAINED_SLOTS"
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
  feed(detector, burst, sustainedSeconds(detector)); // first alarm

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

  Test.assertEqualMessage(
    feed(detector, burst, sustainedSeconds(detector)),
    sustainedSeconds(detector),
    "First burst should alarm"
  );
  // Long enough for the burst to age fully out of the sliding window.
  feed(detector, quiet, detector.WINDOW_SECONDS);
  Test.assertEqualMessage(
    feed(detector, burst, sustainedSeconds(detector)),
    sustainedSeconds(detector),
    "Should be able to alarm again once activity has died down"
  );
  return true;
}

//! The point of SUSTAINED_SLOTS: one violent second is a gesture, not shaking.
//! Even the densest possible single second must stay silent.
(:test)
function testSingleSecondBurstDoesNotAlarm(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  // 12 crossings is the most buildWindowWithCrossings can fit into 25 samples,
  // and comfortably over CROSSING_ALARM_COUNT.
  var hard = buildWindowWithCrossings(12, SAMPLES_PER_SECOND);
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);

  Test.assertEqualMessage(
    feed(detector, hard, 1),
    0,
    "A single second of crossings must not alarm however dense it is"
  );
  Test.assertEqualMessage(
    feed(detector, quiet, detector.WINDOW_SECONDS),
    0,
    "and it must not alarm as it ages out either"
  );
  return true;
}

//! Two active seconds and a gap is still not sustained shaking, even though the
//! count is far over the threshold.
(:test)
function testInterruptedBurstsDoNotAlarm(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var burst = buildWindowWithCrossings(6, SAMPLES_PER_SECOND);
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);

  // 6 + 6 = 12 crossings, over CROSSING_ALARM_COUNT, but only 2 active seconds.
  for (var i = 0; i < 3; i += 1) {
    Test.assertEqualMessage(
      feed(detector, burst, 2) + feed(detector, quiet, 3),
      0,
      "Two active seconds out of five must not alarm"
    );
  }
  return true;
}

//! The run has to be unbroken. Two stretches one second short of the
//! requirement, with a single quiet second between them, are not sustained
//! shaking - even though nothing ever ages out of the window and the total
//! stays far over CROSSING_ALARM_COUNT throughout.
(:test)
function testQuietSecondBreaksTheRun(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  var burst = buildWindowWithCrossings(8, SAMPLES_PER_SECOND);
  var quiet = buildWindowWithCrossings(0, SAMPLES_PER_SECOND);
  var almost = sustainedSeconds(detector) - 1;

  Test.assertEqualMessage(feed(detector, burst, almost), 0, "Run too short");
  Test.assertEqualMessage(feed(detector, quiet, 1), 0, "Pause must reset the run");
  Test.assertEqualMessage(
    feed(detector, burst, almost),
    0,
    "A restarted run must not inherit the seconds before the pause"
  );
  return true;
}

//! The run is measured in slots, not seconds, and that is the whole reason the
//! alarm can insist on 3 s without waiting 5. A signal that is violent for half
//! of every second and still for the other half keeps the window total high
//! indefinitely, yet never builds a run past one slot.
(:test)
function testHalfSecondBurstsNeverBuildARun(logger as Test.Logger) as Boolean {
  var detector = new ShakeDetector();
  primeWarmup(detector);
  // 6 crossings, all inside the first half of the second.
  var halfSecond = buildBurstInFirstSlot(6, SAMPLES_PER_SECOND);

  // 30 crossings in the window, nearly four times CROSSING_ALARM_COUNT.
  Test.assertEqualMessage(
    feed(detector, halfSecond, 30),
    0,
    "A quiet slot must break the run even when the second around it is loud"
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
