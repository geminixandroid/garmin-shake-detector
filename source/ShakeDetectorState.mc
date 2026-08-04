using Toybox.Timer;
import Toybox.Lang;

// Which screen is on top. The quit confirmation needs to time out by itself, so
// the 1 Hz tick has to know whether it is open.
enum {
  MODE_RUNNING,
  MODE_QUITDLG,
}

// Small holder for state that is shared between the view, the delegate and the
// sensor handler: the current screen mode and the mute flag.
class ShakeDetectorState {
  // Mute is deliberately temporary, not a setting - it exists for "I am about
  // to shake my own wrist on purpose" (sport, a bumpy drive), so it expires by
  // itself rather than being left on for days by accident.
  const MUTE_PERIOD_MS as Number = 5 * 60 * 1000;

  var mMode as Number = MODE_RUNNING;
  var mMuted as Boolean = false;
  var mMuteTimer as Timer.Timer? = null;

  function initialize() {
  }

  function getMode() as Number {
    return mMode;
  }

  function setMode(mode as Number) as Void {
    mMode = mode;
  }

  function isMuted() as Boolean {
    return mMuted;
  }

  function toggleMute() as Void {
    if (mMuted) {
      setMuted(false);
    } else {
      setMuted(true);
    }
  }

  function setMuted(muted as Boolean) as Void {
    // Always tear the timer down first: re-muting while a mute is already
    // running must restart the single timer, not leave a second one behind that
    // would un-mute early.
    var timer = mMuteTimer;
    if (timer != null) {
      timer.stop();
      mMuteTimer = null;
    }
    mMuted = muted;
    writeLog("ShakeDetectorState.setMuted()", "muted=" + muted);
    if (muted) {
      timer = new Timer.Timer();
      timer.start(method(:muteTimerCallback), MUTE_PERIOD_MS, false);
      mMuteTimer = timer;
    }
  }

  function muteTimerCallback() as Void {
    writeLog("ShakeDetectorState.muteTimerCallback()", "mute expired");
    mMuted = false;
    mMuteTimer = null;
  }
}
