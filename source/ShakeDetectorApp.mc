using Toybox.Application as App;
using Toybox.WatchUi as Ui;
using Toybox.Timer;
import Toybox.Lang;

class ShakeDetectorApp extends App.AppBase {
  var mState as ShakeDetectorState;
  var mPhone as ShakeDetectorPhone;
  var mSensors as ShakeDetectorSensors;
  var mTimer as Timer.Timer;
  var mView as ShakeDetectorView?;
  var mDelegate as ShakeDetectorDelegate?;
  var mPhoneStateVersion as Number = 0;

  function initialize() {
    AppBase.initialize();
    // Before anything can alert: an alarm app must never sit silent waiting for
    // the user to discover the settings menu.
    initSettingsDefaults();
    mState = new ShakeDetectorState();
    mPhone = new ShakeDetectorPhone();
    mSensors = new ShakeDetectorSensors(mState, mPhone);
    mTimer = new Timer.Timer();
  }

  function onStart(state as Dictionary or Null) as Void {
    writeLog("ShakeDetectorApp.onStart()", "");
    // Subscribed here rather than from the view's onLayout(), which can run more
    // than once and would register a second listener.
    mSensors.onStart();
    mTimer.start(method(:onTick), 1000, true);
  }

  function onStop(state as Dictionary or Null) as Void {
    writeLog("ShakeDetectorApp.onStop()", "");
    mTimer.stop();
    mSensors.onStop();
  }

  function getInitialView() as [Ui.Views] or [Ui.Views, Ui.InputDelegates] {
    var view = new ShakeDetectorView(mState, mSensors);
    var delegate = new ShakeDetectorDelegate(view, mState, mPhone);
    mView = view;
    mDelegate = delegate;
    return [view, delegate] as [Ui.Views, Ui.InputDelegates];
  }

  function onTick() as Void {
    var view = mView;
    if (view != null) {
      view.onTick();
    }
    var delegate = mDelegate;
    if (delegate != null) {
      delegate.onTick();
    }
    mPhone.onTick();

    // Web request callbacks repaint nothing by themselves, so the setup screen only
    // learns a response arrived because of this. Comparing a version counter rather
    // than an "is busy" flag matters: SECURE_CONNECTION_REQUIRED comes back with no
    // network involved at all, so a request can start and fail between two ticks
    // and the flag would never be seen as true.
    var version = mPhone.getStateVersion();
    if (version != mPhoneStateVersion) {
      mPhoneStateVersion = version;
      Ui.requestUpdate();
    }
  }
}
