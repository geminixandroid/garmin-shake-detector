using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System;
using Toybox.Time;
import Toybox.Application.Storage;
import Toybox.Lang;

class ShakeDetectorView extends Ui.View {
  var mState as ShakeDetectorState;
  var mSensors as ShakeDetectorSensors;

  // One layout class for every device - the screen shape only picks different
  // fractions inside it. Set in onLayout(), which always runs before the first
  // onUpdate().
  var mScreenLayout as ShakeDetectorLayout?;

  // The status line shows the app version for the first few seconds after launch,
  // which is the only place a version is visible on the watch at all - handy when you
  // are not sure whether the build you just sideloaded is the one running.
  const VERSION_DISPLAY_SECONDS as Number = 5;
  var mSecondsRunning as Number = 0;

  var mStatusStr as String;
  var mLastMinute as Number = -1;
  var mIcons as Array<Number> = [] as Array<Number>;
  var mWasActive as Boolean = false;

  var strOk as String;
  var strAlarm as String;
  var strMute as String;
  var strMuteAlarm as String;
  var strSilent as String;
  var strVersion as String;

  function initialize(
    state as ShakeDetectorState,
    sensors as ShakeDetectorSensors
  ) {
    View.initialize();
    mState = state;
    mSensors = sensors;
    strOk = Ui.loadResource(Rez.Strings.Status_ok).toString();
    strAlarm = Ui.loadResource(Rez.Strings.Status_alarm).toString();
    strMute = Ui.loadResource(Rez.Strings.Status_mute).toString();
    strMuteAlarm = Ui.loadResource(Rez.Strings.Status_mute_alarm).toString();
    strSilent = Ui.loadResource(Rez.Strings.Status_silent).toString();
    strVersion = Ui.loadResource(Rez.Strings.VersionId).toString();
    // Seed both, so the very first onUpdate() - which happens before the first
    // tick - already paints the real state instead of an empty icon row.
    mStatusStr = statusString();
    mIcons = indicatorIcons();
    writeLog("ShakeDetectorView.initialize()", "Complete");
  }

  function onLayout(dc as Gfx.Dc) as Void {
    // SCREEN_SHAPE_SEMI_OCTAGON only appeared with Instinct, so on an older
    // device the constant itself is missing and reading it would throw. Any
    // device that does not know the constant cannot be Instinct-shaped anyway.
    var isInstinctShape = false;
    if (System has :SCREEN_SHAPE_SEMI_OCTAGON) {
      isInstinctShape =
        System.getDeviceSettings().screenShape == System.SCREEN_SHAPE_SEMI_OCTAGON;
    }
    mScreenLayout = new ShakeDetectorLayout(dc, isInstinctShape);
    writeLog(
      "ShakeDetectorView.onLayout()",
      Lang.format("$1$x$2$, instinct=$3$", [
        dc.getWidth(),
        dc.getHeight(),
        isInstinctShape,
      ])
    );
  }

  // Called once a second from the app timer.
  //
  // Redraw cadence is deliberately adaptive: while there is any activity in the
  // window the chart is worth animating once a second, but a still wrist - which
  // is the normal case, for hours at a time - falls back to redrawing only when
  // something actually changed. The accelerometer dominates this app's power
  // draw, but there is no reason to spend CPU repainting an unchanged screen.
  function onTick() as Void {
    mSecondsRunning += 1;
    var status = statusString();
    var icons = indicatorIcons();
    var currentMinute = System.getClockTime().min;
    var trace = mSensors.getTrace();
    var active = trace[trace.size() - 1] > 0;
    if (
      active ||
      mWasActive || // one last repaint so the final bars clear
      !status.equals(mStatusStr) ||
      !iconsEqual(icons, mIcons) ||
      currentMinute != mLastMinute
    ) {
      mStatusStr = status;
      mIcons = icons;
      mLastMinute = currentMinute;
      mWasActive = active;
      Ui.requestUpdate();
    }
  }

  // Which alert channels are armed, as a row of pictograms. Absence means "off",
  // and when nothing at all can alert - muted, or every channel switched off -
  // the struck-through speaker is shown on its own rather than an empty row.
  function indicatorIcons() as Array<Number> {
    if (mState.isMuted()) {
      return [ICON_SILENT] as Array<Number>;
    }
    var icons = [] as Array<Number>;
    if (isSettingEnabled(MENUITEM_VIBRATION)) {
      icons.add(ICON_VIBE);
    }
    if (isSettingEnabled(MENUITEM_SOUND)) {
      icons.add(ICON_SOUND);
    }
    if (isSettingEnabled(MENUITEM_LIGHT)) {
      icons.add(ICON_LIGHT);
    }
    if (isSettingEnabled(MENUITEM_PHONE_ALERT)) {
      icons.add(ICON_PHONE);
    }
    if (icons.size() == 0) {
      icons.add(ICON_SILENT);
    }

    return icons;
  }

  function iconsEqual(a as Array<Number>, b as Array<Number>) as Boolean {
    if (a.size() != b.size()) {
      return false;
    }
    for (var i = 0; i < a.size(); i += 1) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  // Exactly one thing is shown on the status line, in this order of precedence.
  // Mute outranks a plain alarm because a silenced app has to look silenced -
  // but a detection during mute still shows (as "MUTE!"), so it is never
  // invisible that something fired.
  function statusString() as String {
    var alarmActive = mSensors.isAlarmActive();
    if (mState.isMuted()) {
      return alarmActive ? strMuteAlarm : strMute;
    }
    if (alarmActive) {
      return strAlarm;
    }
    // Version only while nothing is happening, and only at the start: an alarm or a
    // mute in the first seconds still has to be visible - a version number is never
    // more important than the state of the alarm.
    if (mSecondsRunning < VERSION_DISPLAY_SECONDS) {
      return strVersion;
    }
    if (
      !isSettingEnabled(MENUITEM_VIBRATION) &&
      !isSettingEnabled(MENUITEM_SOUND) &&
      !isSettingEnabled(MENUITEM_LIGHT) &&
      !isSettingEnabled(MENUITEM_PHONE_ALERT)
    ) {
      // Detection still runs, but nothing can be reported - say so rather than
      // looking like a healthy "OK".
      return strSilent;
    }
    return strOk;
  }

  function onUpdate(dc as Gfx.Dc) as Void {
    var clockTime = System.getClockTime();
    var timeString = Lang.format("$1$:$2$", [
      clockTime.hour.format("%02d"),
      clockTime.min.format("%02d"),
    ]);

    dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
    dc.clear();
    dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);

    var layout = mScreenLayout as ShakeDetectorLayout;
    layout.drawHeader(
      dc,
      timeString,
      System.getSystemStats().battery
    );
    layout.drawGraph(dc, mSensors.getTrace(), mSensors.getAlarmThreshold());
    layout.drawIndicators(dc, mIcons);
    layout.drawStatus(dc, mStatusStr);
  }
}

class ShakeDetectorDelegate extends Ui.BehaviorDelegate {
  // The quit dialog closes itself, so a stray press cannot leave the app parked
  // in a dialog where a detection would go unnoticed.
  const QUIT_TIMEOUT_SECS as Number = 10;

  var mView as ShakeDetectorView;
  var mState as ShakeDetectorState;
  var mPhone as ShakeDetectorPhone;
  var mQuitDlgOpenTime as Number = 0;

  function initialize(
    view as ShakeDetectorView,
    state as ShakeDetectorState,
    phone as ShakeDetectorPhone
  ) {
    BehaviorDelegate.initialize();
    mView = view;
    mState = state;
    mPhone = phone;
    mState.setMode(MODE_RUNNING);
  }

  function onTick() as Void {
    if (mState.getMode() == MODE_QUITDLG) {
      var openSecs = Time.now().value() - mQuitDlgOpenTime;
      if (openSecs > QUIT_TIMEOUT_SECS) {
        writeLog("ShakeDetectorDelegate.onTick()", "Quit dialog timed out");
        mState.setMode(MODE_RUNNING);
        Ui.popView(Ui.SLIDE_IMMEDIATE);
      }
    }
  }

  //! Select (the ENTER/START button, or a tap on touch devices) toggles mute.
  //! Handled as a behaviour rather than a raw KEY_ENTER so it works on both
  //! button and touchscreen watches.
  function onSelect() as Boolean {
    mState.toggleMute();
    Ui.requestUpdate();
    return true;
  }

  //! Menu2 arrived with API 3.0, but this app declares minSdkVersion 2.4.0 to
  //! reach as many watches as possible - so on a device without it, fall back to
  //! the 1.x-era Ui.Menu, which cannot show toggle switches and has to spell the
  //! state out in the label instead.
  function onMenu() as Boolean {
    if (Ui has :Menu2) {
      var menu = new Ui.Menu2({
        :title => Ui.loadResource(Rez.Strings.Settings_title).toString(),
      });
      menu.addItem(
        new Ui.ToggleMenuItem(
          Ui.loadResource(Rez.Strings.Vibration_title).toString(),
          Ui.loadResource(Rez.Strings.Vibration_desc).toString(),
          MENUITEM_VIBRATION,
          isSettingEnabled(MENUITEM_VIBRATION),
          null
        )
      );
      menu.addItem(
        new Ui.ToggleMenuItem(
          Ui.loadResource(Rez.Strings.Sound_title).toString(),
          Ui.loadResource(Rez.Strings.Sound_desc).toString(),
          MENUITEM_SOUND,
          isSettingEnabled(MENUITEM_SOUND),
          null
        )
      );
      menu.addItem(
        new Ui.ToggleMenuItem(
          Ui.loadResource(Rez.Strings.Light_title).toString(),
          Ui.loadResource(Rez.Strings.Light_desc).toString(),
          MENUITEM_LIGHT,
          isSettingEnabled(MENUITEM_LIGHT),
          null
        )
      );
      menu.addItem(
        new Ui.ToggleMenuItem(
          Ui.loadResource(Rez.Strings.Phone_title).toString(),
          Ui.loadResource(Rez.Strings.Phone_desc).toString(),
          MENUITEM_PHONE_ALERT,
          isSettingEnabled(MENUITEM_PHONE_ALERT),
          null
        )
      );
      // Not toggles: selecting these opens a screen.
      menu.addItem(
        new Ui.MenuItem(
          Ui.loadResource(Rez.Strings.Test_title).toString(),
          Ui.loadResource(Rez.Strings.Test_desc).toString(),
          :testAlarm,
          null
        )
      );
      menu.addItem(
        new Ui.MenuItem(
          Ui.loadResource(Rez.Strings.Link_title).toString(),
          Ui.loadResource(Rez.Strings.Link_desc).toString(),
          :link,
          null
        )
      );
      Ui.pushView(
        menu,
        new ShakeDetectorSettingsMenuDelegate(mPhone, mView.mSensors, mState),
        Ui.SLIDE_IMMEDIATE
      );
    } else {
      var menu = new Ui.Menu();
      menu.setTitle(Ui.loadResource(Rez.Strings.Settings_title).toString());
      menu.addItem(legacyLabel(Rez.Strings.Vibration_title, MENUITEM_VIBRATION), :vibration);
      menu.addItem(legacyLabel(Rez.Strings.Sound_title, MENUITEM_SOUND), :sound);
      menu.addItem(legacyLabel(Rez.Strings.Light_title, MENUITEM_LIGHT), :light);
      menu.addItem(legacyLabel(Rez.Strings.Phone_title, MENUITEM_PHONE_ALERT), :phone);
      menu.addItem(Ui.loadResource(Rez.Strings.Test_title).toString(), :testAlarm);
      menu.addItem(Ui.loadResource(Rez.Strings.Link_title).toString(), :link);
      Ui.pushView(
        menu,
        new LegacySettingsMenuDelegate(mPhone, mView.mSensors, mState),
        Ui.SLIDE_IMMEDIATE
      );
    }
    return true;
  }

  //! "Vibration: ON" - the legacy menu has no switch widget to show state with.
  function legacyLabel(titleResource as Lang.ResourceId, menuItem as Number) as String {
    var state = isSettingEnabled(menuItem)
      ? Ui.loadResource(Rez.Strings.Label_on).toString()
      : Ui.loadResource(Rez.Strings.Label_off).toString();
    return Ui.loadResource(titleResource).toString() + ": " + state;
  }

  function onBack() as Boolean {
    writeLog("ShakeDetectorDelegate.onBack()", "");
    var quitString = Ui.loadResource(Rez.Strings.Exit_app_confirmation).toString();
    mState.setMode(MODE_QUITDLG);
    mQuitDlgOpenTime = Time.now().value();
    Ui.pushView(
      new Ui.Confirmation(quitString),
      new QuitDelegate(mState),
      Ui.SLIDE_IMMEDIATE
    );
    return true;
  }
}

class QuitDelegate extends Ui.ConfirmationDelegate {
  var mState as ShakeDetectorState;

  function initialize(state as ShakeDetectorState) {
    ConfirmationDelegate.initialize();
    mState = state;
  }

  function onResponse(value as Ui.Confirm) as Boolean {
    writeLog("QuitDelegate.onResponse()", "Response = " + value);
    if (value == Ui.CONFIRM_YES) {
      // The system pops the confirmation itself, so this pops the main view -
      // which is what actually exits the app.
      Ui.popView(Ui.SLIDE_IMMEDIATE);
    } else {
      mState.setMode(MODE_RUNNING);
    }
    return true;
  }
}

//! Handles the API 3.0+ menu. Only ever instantiated when Ui has :Menu2, so on an
//! older device this class is never referenced.
class ShakeDetectorSettingsMenuDelegate extends Ui.Menu2InputDelegate {
  var mPhone as ShakeDetectorPhone;
  var mSensors as ShakeDetectorSensors;
  var mState as ShakeDetectorState;

  function initialize(
    phone as ShakeDetectorPhone,
    sensors as ShakeDetectorSensors,
    state as ShakeDetectorState
  ) {
    Menu2InputDelegate.initialize();
    mPhone = phone;
    mSensors = sensors;
    mState = state;
  }

  function onSelect(menuItem as Ui.MenuItem) as Void {
    if (menuItem instanceof Ui.ToggleMenuItem) {
      writeLog("SettingsMenuDelegate.onSelect()", "id=" + menuItem.getId());
      Storage.setValue(menuItem.getId() as Number, menuItem.isEnabled());
      return;
    }
    var id = menuItem.getId();
    if (id == :link) {
      Ui.pushView(
        new ShakeDetectorLinkView(mPhone),
        new ShakeDetectorLinkDelegate(),
        Ui.SLIDE_IMMEDIATE
      );
    } else if (id == :testAlarm) {
      Ui.pushView(
        new ShakeDetectorTestView(mSensors, mState, mPhone),
        new ShakeDetectorTestDelegate(),
        Ui.SLIDE_IMMEDIATE
      );
    }
  }
}

//! Handles the 1.x-era menu on devices without Menu2. The old menu closes itself
//! after a selection and cannot be updated in place, so each pick just flips the
//! setting; re-opening the menu shows the new state in the label.
class LegacySettingsMenuDelegate extends Ui.MenuInputDelegate {
  var mPhone as ShakeDetectorPhone;
  var mSensors as ShakeDetectorSensors;
  var mState as ShakeDetectorState;

  function initialize(
    phone as ShakeDetectorPhone,
    sensors as ShakeDetectorSensors,
    state as ShakeDetectorState
  ) {
    MenuInputDelegate.initialize();
    mPhone = phone;
    mSensors = sensors;
    mState = state;
  }

  function onMenuItem(item as Symbol) as Void {
    if (item == :link) {
      Ui.pushView(
        new ShakeDetectorLinkView(mPhone),
        new ShakeDetectorLinkDelegate(),
        Ui.SLIDE_IMMEDIATE
      );
      return;
    }
    if (item == :testAlarm) {
      Ui.pushView(
        new ShakeDetectorTestView(mSensors, mState, mPhone),
        new ShakeDetectorTestDelegate(),
        Ui.SLIDE_IMMEDIATE
      );
      return;
    }
    var menuItem = MENUITEM_VIBRATION;
    if (item == :sound) {
      menuItem = MENUITEM_SOUND;
    } else if (item == :light) {
      menuItem = MENUITEM_LIGHT;
    } else if (item == :phone) {
      menuItem = MENUITEM_PHONE_ALERT;
    }
    var enabled = !isSettingEnabled(menuItem);
    writeLog("LegacySettingsMenuDelegate.onMenuItem()", item + " -> " + enabled);
    Storage.setValue(menuItem, enabled);
  }
}
