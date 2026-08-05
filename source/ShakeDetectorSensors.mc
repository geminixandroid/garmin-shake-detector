using Toybox.Sensor;
using Toybox.Attention;
import Toybox.Lang;

// Owns the accelerometer subscription, feeds it to ShakeDetector and turns a
// detection into vibration/sound/backlight.
class ShakeDetectorSensors {
  const SAMPLE_PERIOD as Number = 1; // seconds per callback
  const SAMPLE_FREQUENCY as Number = 25; // Hz

  var mDetector as ShakeDetector;
  var mState as ShakeDetectorState;
  var mPhone as ShakeDetectorPhone;

  function initialize(state as ShakeDetectorState, phone as ShakeDetectorPhone) {
    mState = state;
    mPhone = phone;
    mDetector = new ShakeDetector();
  }

  function isAlarmActive() as Boolean {
    return mDetector.isAlarmActive();
  }

  //! Window-total history for the on-screen chart, oldest first.
  function getTrace() as Array<Number> {
    return mDetector.getTrace();
  }

  //! The value the chart's threshold line marks.
  function getAlarmThreshold() as Number {
    return mDetector.CROSSING_ALARM_COUNT;
  }

  function onStart() as Void {
    var tagStr = "ShakeDetectorSensors.onStart()";
    writeLog(tagStr, "maxSampleRate = " + Sensor.getMaxSampleRate());
    var options = {
      :period => SAMPLE_PERIOD,
      :accelerometer => {
        :enabled => true,
        :sampleRate => SAMPLE_FREQUENCY,
      },
    };
    try {
      Sensor.registerSensorDataListener(method(:accel_callback), options);
      writeLog(tagStr, "Registered for accelerometer data");
    } catch (e) {
      writeLog("*** ERROR - " + tagStr, e.getErrorMessage());
    }
  }

  function onStop() as Void {
    writeLog("ShakeDetectorSensors.onStop()", "");
    Sensor.unregisterSensorDataListener();
    Sensor.setEnabledSensors([] as Array<Sensor.SensorType>);
    // Not part of the documented API, but required to avoid the watch draining
    // its battery after the app exits - a long standing Garmin bug:
    // https://forums.garmin.com/developer/connect-iq/f/discussion/872/battery-drain-when-connectiq-app-is-not-running
    Sensor.enableSensorEvents(null);
  }

  // Called once a second by the system with SAMPLE_FREQUENCY samples per axis,
  // in milli-G.
  function accel_callback(sensorData as Sensor.SensorData) as Void {
    var tagStr = "ShakeDetectorSensors.accel_callback()";
    var accelData = sensorData.accelerometerData;
    if (accelData == null) {
      writeLog(tagStr, "No accelerometer data in callback");
      return;
    }
    var x = accelData.x;
    var y = accelData.y;
    var z = accelData.z;
    if (x == null || y == null || z == null) {
      writeLog(tagStr, "Accelerometer data has a null axis");
      return;
    }

    var nSamples = SAMPLE_PERIOD * SAMPLE_FREQUENCY;
    if (x.size() != nSamples || y.size() != nSamples || z.size() != nSamples) {
      // Some devices occasionally deliver a short buffer. Skip the second
      // rather than padding it with zeroes: to the detector a zeroed sample
      // looks like a 1000 mG excursion and would inject a phantom crossing.
      writeLog(tagStr, "Unexpected sample count " + x.size() + " - skipping");
      return;
    }

    // The detector only ever needs one second at a time, so the samples go
    // straight from the sensor buffer into it - no local copy of the window is
    // kept (nothing in this app has to re-read past samples, and RAM on these
    // watches is scarce).
    if (mDetector.addSampleWindow(x, y, z, 0, nSamples)) {
      writeLog(tagStr, "Shake detected - raising alarm");
      triggerAlarm();
    }
  }

  // Raise the alarm. The audience is whoever is nearby, not the wearer - during an
  // event they cannot act on it. Each channel is checked twice: once for whether the
  // device supports it at all, once for whether the user left it enabled.
  // Settings are read from Storage here rather than cached at start-up, so
  // toggling one applies to the very next alarm without a restart.
  function triggerAlarm() as Void {
    if (mState.isMuted()) {
      writeLog("ShakeDetectorSensors.triggerAlarm()", "Muted - not alerting");
      return;
    }

    if (Attention has :playTone && isSettingEnabled(MENUITEM_SOUND)) {
      Attention.playTone(Attention.TONE_ALERT_HI);
    }

    if (Attention has :backlight && isSettingEnabled(MENUITEM_LIGHT)) {
      try {
        Attention.backlight(true);
      } catch (ex) {
        // Toybox.Attention.BacklightOnTooLongException - must not be allowed to
        // propagate, or a failed backlight would kill the vibration below.
        writeLog("ShakeDetectorSensors.triggerAlarm()", "backlight refused");
      }
    }

    if (Attention has :vibrate && isSettingEnabled(MENUITEM_VIBRATION)) {
      var vibeData = [
        new Attention.VibeProfile(50, 500),
        new Attention.VibeProfile(0, 500),
        new Attention.VibeProfile(50, 500),
        new Attention.VibeProfile(0, 500),
        new Attention.VibeProfile(50, 500),
      ];
      Attention.vibrate(vibeData as Array<Attention.VibeProfile>);
    }

    // Last, deliberately: the wrist alert must not wait on the network, and this
    // call is fire-and-forget. The phone is an amplifier, not a dependency.
    mPhone.sendAlert();
  }
}
