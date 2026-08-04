using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
import Toybox.Lang;

// Fires the real alarm path on demand and reports what happened.
//
// It calls the same triggerAlarm() a detection calls - not a private copy - so what
// this screen proves is what will actually happen at night. That includes respecting
// mute and the Phone alert setting: a test that quietly bypassed them would report
// success on a configuration that stays silent when it matters.
//
// The point of the screen is the phone result. Vibration, tone and backlight you can
// feel; whether the POST reached the server is otherwise invisible.
class ShakeDetectorTestView extends Ui.View {
  // Same reason as the setup screen: Instinct's round sub-window occupies the top
  // right corner down to about 44% of the height, and centred text drawn higher than
  // that disappears underneath it.
  const TITLE_Y_FRACTION = 0.44;
  const LOCAL_Y_FRACTION = 0.62;
  const PHONE_Y_FRACTION = 0.75;

  var mSensors as ShakeDetectorSensors;
  var mState as ShakeDetectorState;
  var mPhone as ShakeDetectorPhone;
  var mFired as Boolean = false;

  var strTitle as String;
  var strLocalFired as String;
  var strMuted as String;
  var strPhoneOff as String;
  var strPhoneSending as String;
  var strPhoneSent as String;
  var strPhoneFailed as String;

  function initialize(
    sensors as ShakeDetectorSensors,
    state as ShakeDetectorState,
    phone as ShakeDetectorPhone
  ) {
    View.initialize();
    mSensors = sensors;
    mState = state;
    mPhone = phone;
    strTitle = Ui.loadResource(Rez.Strings.Test_title).toString();
    strLocalFired = Ui.loadResource(Rez.Strings.Test_local_fired).toString();
    strMuted = Ui.loadResource(Rez.Strings.Test_muted).toString();
    strPhoneOff = Ui.loadResource(Rez.Strings.Test_phone_off).toString();
    strPhoneSending = Ui.loadResource(Rez.Strings.Test_phone_sending).toString();
    strPhoneSent = Ui.loadResource(Rez.Strings.Test_phone_sent).toString();
    strPhoneFailed = Ui.loadResource(Rez.Strings.Test_phone_failed).toString();
  }

  //! Fired from onShow rather than the constructor, so the screen is already up when
  //! the watch starts buzzing - otherwise the vibration happens against the menu.
  function onShow() as Void {
    if (!mFired) {
      mFired = true;
      writeLog("ShakeDetectorTestView", "manual alarm test");
      // The phone alert is rate limited to one per minute; an explicit test must not
      // be swallowed by that, or testing twice looks like a failure.
      mPhone.resetAlertThrottle();
      mSensors.triggerAlarm();
    }
  }

  function onUpdate(dc as Gfx.Dc) as Void {
    var width = dc.getWidth();
    var height = dc.getHeight();
    var centreX = width / 2;

    dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
    dc.clear();
    dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);

    dc.drawText(centreX, height * 0.16, Gfx.FONT_MEDIUM, strTitle, Gfx.TEXT_JUSTIFY_CENTER);
    dc.drawText(
      centreX,
      height * 0.42,
      Gfx.FONT_XTINY,
      mState.isMuted() ? strMuted : strLocalFired,
      Gfx.TEXT_JUSTIFY_CENTER
    );
    dc.drawText(
      centreX,
      height * 0.58,
      Gfx.FONT_XTINY,
      phoneStatus(),
      Gfx.TEXT_JUSTIFY_CENTER
    );
  }

  function phoneStatus() as String {
    if (mState.isMuted() || !isSettingEnabled(MENUITEM_PHONE_ALERT)) {
      return strPhoneOff;
    }
    if (!mPhone.hasAlertResult()) {
      return mPhone.isRequestInProgress() ? strPhoneSending : strPhoneFailed;
    }
    if (mPhone.wasAlertDelivered()) {
      return strPhoneSent;
    }
    return strPhoneFailed + " " + mPhone.getLastErrorCode();
  }
}

class ShakeDetectorTestDelegate extends Ui.BehaviorDelegate {
  function initialize() {
    BehaviorDelegate.initialize();
  }

  function onBack() as Boolean {
    Ui.popView(Ui.SLIDE_IMMEDIATE);
    return true;
  }

  function onSelect() as Boolean {
    Ui.popView(Ui.SLIDE_IMMEDIATE);
    return true;
  }
}
