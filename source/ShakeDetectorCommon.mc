using Toybox.System;
import Toybox.Application.Storage;
import Toybox.Lang;

function writeLog(tagStr as String, msgStr as String?) as Void {
  var myTime = System.getClockTime();
  var timeString = Lang.format("$1$:$2$:$3$", [
    myTime.hour.format("%02d"),
    myTime.min.format("%02d"),
    myTime.sec.format("%02d"),
  ]);
  System.println(timeString + " : " + tagStr + " : " + msgStr);
}

// Storage keys for the settings menu toggles - also the ids of the
// ToggleMenuItems themselves, so onSelect() can save straight from the id.
enum {
  MENUITEM_VIBRATION,
  MENUITEM_SOUND,
  MENUITEM_LIGHT,
  MENUITEM_PHONE_ALERT,
}

// Storage key for this watch's device id. A string key, deliberately: the numeric
// keys above are menu item ids and would collide.
const STORAGE_DEVICE_ID = "deviceId";

// Every alert channel is opt-OUT: on a fresh install all three are enabled, and
// the user turns off what they don't want. An alarm app that starts up silent
// until someone finds the menu is worse than useless, so the defaults are set
// as early as possible (App.initialize()) rather than when the menu is first
// built.
function initSettingsDefaults() as Void {
  var items = [
    MENUITEM_VIBRATION,
    MENUITEM_SOUND,
    MENUITEM_LIGHT,
    MENUITEM_PHONE_ALERT,
  ];
  for (var i = 0; i < items.size(); i += 1) {
    if (Storage.getValue(items[i] as Number) == null) {
      Storage.setValue(items[i] as Number, true);
    }
  }
}

function isSettingEnabled(menuItem as Number) as Boolean {
  return Storage.getValue(menuItem) ? true : false;
}
