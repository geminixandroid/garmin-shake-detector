using Toybox.Communications as Comm;
using Toybox.System;
using Toybox.Time;
using Toybox.Math;
import Toybox.Application.Storage;
import Toybox.Lang;

// Everything that talks to the ShakeDetector backend, kept in one class so the
// detector and the UI stay unaware of the network.
//
// Two operations, and nothing else:
//   1. requestShortLink() - POST /api/shorten, once, during setup. The watch shows
//      the returned code; the wearer types it into a phone browser and subscribes
//      to push there.
//   2. sendAlert() - POST /api/alert when the detector fires, so the phone makes a
//      noise the watch cannot.
//
// The phone is an amplifier, never a dependency: if it is absent, out of signal or
// the server is down, the watch alerts exactly as it would have anyway.
class ShakeDetectorPhone {
  // In the simulator the request is made from this PC, so a local server is
  // reachable at 127.0.0.1. On a real watch the request is proxied by Garmin
  // Connect *on the phone*, so this has to be a public https host that the phone
  // can reach - a localhost URL would hit the phone's own loopback.
  //
  // SERVER_HOST must be the same host without the scheme. Kept as a second
  // constant rather than parsed out of the first: the link screen needs it, and
  // string surgery on a value that is fixed at build time is pure ceremony.
  // https is not a preference: Connect IQ refuses a plain http URL outright with
  // SECURE_CONNECTION_REQUIRED (-1001), before any request leaves the watch.
  const SERVER_URL as String = "https://shakedetector.geminixandroid.com";
  const SERVER_HOST as String = "shakedetector.geminixandroid.com";

  // No retries and no queue: an alarm is a real-time event, and a stale ping is
  // worth nothing. One request in flight, abandoned after this long.
  const REQUEST_TIMEOUT_SECS as Number = 4;

  // Minimum gap between two alerts sent to the phone.
  //
  // Deliberately decoupled from the detector's REPEAT_INTERVAL_SECONDS, which is 5:
  // the wrist should keep buzzing that often, because that is the local alarm and the
  // wearer may be asleep - but the phone only needs telling once. Without this a
  // one-minute event produced about a dozen push notifications, which is how a phone
  // alarm trains its owner to swipe it away.
  //
  // The first alert after a quiet period always goes through; only the repeats within
  // the window are dropped.
  const ALERT_MIN_INTERVAL_SECS as Number = 60;
  var mLastAlertSentSecs as Number = 0;

  var mRequestInProgress as Boolean = false;
  var mRequestStartSecs as Number = 0;

  // Setup state, for the link screen to display.
  var mShortCode as String? = null;
  var mLastErrorCode as Number = 0;

  // Outcome of the most recent alert POST, so the test screen can say whether the
  // push actually went out. A plain error code is not enough: it stays set from a
  // previous failure, so "no error" cannot be read as "delivered".
  var mHasAlertResult as Boolean = false;
  var mLastAlertOk as Boolean = false;

  // Bumped on every state change. The link screen has no way to know a response
  // arrived - web request callbacks repaint nothing - so the app tick watches this
  // and repaints when it moves.
  //
  // A plain "is a request in flight" check is not enough: some failures come back
  // *immediately* (SECURE_CONNECTION_REQUIRED needs no network at all), so the
  // flag can go up and down between two ticks and the screen would sit on
  // "Requesting..." forever.
  var mStateVersion as Number = 0;

  function initialize() {
  }

  //! This watch's id, generated once and kept in Storage.
  //!
  //! Connect IQ exposes no stable per-device identifier, so it has to be invented.
  //! Note this id is effectively a bearer token - anything that knows it can send
  //! alerts for this watch - and Monkey C has no cryptographic RNG, only
  //! Math.rand(). That is why the server must never publish a list of device ids.
  function getDeviceId() as String {
    var stored = Storage.getValue(STORAGE_DEVICE_ID);
    if (stored != null) {
      return stored.toString();
    }
    // Seed from the clock so two watches starting up do not agree, then take the
    // low bits of successive rand() calls.
    Math.srand(Time.now().value() + System.getTimer());
    var chars = "0123456789abcdef";
    var id = "";
    for (var i = 0; i < 32; i += 1) {
      var nibble = Math.rand() % 16;
      id += chars.substring(nibble, nibble + 1);
    }
    Storage.setValue(STORAGE_DEVICE_ID, id);
    writeLog("ShakeDetectorPhone.getDeviceId()", "generated new device id");
    return id;
  }

  function getShortCode() as String? {
    return mShortCode;
  }

  function getLastErrorCode() as Number {
    return mLastErrorCode;
  }

  function isRequestInProgress() as Boolean {
    return mRequestInProgress;
  }

  //! Host part of the URL, for the link screen: the wearer needs to type
  //! "<host>/s/<code>", so both halves have to be on screen.
  function getServerHost() as String {
    return SERVER_HOST;
  }

  //! Ask the server for a short setup link. Called from the settings menu, not
  //! automatically - it is a one-off during setup, and there is no reason to touch
  //! the network on every start-up.
  function requestShortLink() as Void {
    if (mRequestInProgress) {
      return;
    }
    mShortCode = null;
    mLastErrorCode = 0;
    beginRequest();
    try {
      Comm.makeWebRequest(
        SERVER_URL + "/api/shorten",
        { "deviceId" => getDeviceId() } as Dictionary<Object, Object>,
        // JSON, not form encoding: the server only mounts express.json(). The
        // options have to be an inline literal - makeWebRequest expects a
        // structurally typed dictionary, which the compiler can only verify here.
        {
          :method => Comm.HTTP_REQUEST_METHOD_POST,
          :headers => { "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON },
          :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON,
        },
        method(:onShortLinkResponse)
      );
    } catch (e) {
      mRequestInProgress = false;
      writeLog("*** ERROR - ShakeDetectorPhone.requestShortLink()", e.getErrorMessage());
    }
  }

  //! Tell the server a detection happened, so it can push to the phone.
  //!
  //! Deliberately fire-and-forget, and deliberately *after* the watch has already
  //! vibrated: nothing here may delay the local alert. No timestamp is sent - the
  //! server stamps it, which avoids both the watch's clock being wrong and the
  //! fact that epoch milliseconds do not fit in Monkey C's 32-bit Number.
  function sendAlert() as Void {
    if (!isSettingEnabled(MENUITEM_PHONE_ALERT)) {
      return;
    }
    if (mRequestInProgress) {
      writeLog("ShakeDetectorPhone.sendAlert()", "request already in flight - skipped");
      return;
    }
    var now = Time.now().value();
    if (mLastAlertSentSecs != 0 && now - mLastAlertSentSecs < ALERT_MIN_INTERVAL_SECS) {
      writeLog("ShakeDetectorPhone.sendAlert()", "throttled - phone told recently");
      return;
    }
    mLastAlertSentSecs = now;
    mHasAlertResult = false;
    beginRequest();
    try {
      Comm.makeWebRequest(
        SERVER_URL + "/api/alert",
        { "deviceId" => getDeviceId() } as Dictionary<Object, Object>,
        {
          :method => Comm.HTTP_REQUEST_METHOD_POST,
          :headers => { "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON },
          :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON,
        },
        method(:onAlertResponse)
      );
    } catch (e) {
      mRequestInProgress = false;
      writeLog("*** ERROR - ShakeDetectorPhone.sendAlert()", e.getErrorMessage());
    }
  }

  function beginRequest() as Void {
    mRequestInProgress = true;
    mRequestStartSecs = Time.now().value();
    mStateVersion += 1;
  }

  function endRequest(errorCode as Number) as Void {
    mRequestInProgress = false;
    if (errorCode != 0) {
      mLastErrorCode = errorCode;
    }
    mStateVersion += 1;
  }

  function getStateVersion() as Number {
    return mStateVersion;
  }

  //! Forget that the phone was told recently, so the next alert goes out immediately.
  //!
  //! Only for the manual test screen: without it, testing twice inside a minute would
  //! silently send nothing and look like a broken setup. The throttle is anti-spam, not
  //! a user setting, so bypassing it for an explicit manual test does not misrepresent
  //! how the app behaves at night.
  function resetAlertThrottle() as Void {
    mLastAlertSentSecs = 0;
  }

  //! Has a response to the last alert POST arrived yet?
  function hasAlertResult() as Boolean {
    return mHasAlertResult;
  }

  //! Was that response a success? Only meaningful once hasAlertResult() is true.
  function wasAlertDelivered() as Boolean {
    return mLastAlertOk;
  }

  // The `data` parameter is typed as the full union Communications hands to a
  // response callback - narrowing it to Dictionary? makes the compiler complain
  // that the method does not match makeWebRequest's expected signature.
  function onShortLinkResponse(
    responseCode as Number,
    data as Null or Dictionary or String or Toybox.PersistedContent.Iterator
  ) as Void {
    if (responseCode == 200 && data instanceof Dictionary) {
      var code = data.get("shortCode");
      if (code != null) {
        mShortCode = code.toString();
        endRequest(0);
        writeLog("ShakeDetectorPhone", "short code = " + mShortCode);
        return;
      }
    }
    endRequest(responseCode);
    writeLog("ShakeDetectorPhone", "shorten failed, code = " + responseCode);
  }

  function onAlertResponse(
    responseCode as Number,
    data as Null or Dictionary or String or Toybox.PersistedContent.Iterator
  ) as Void {
    mHasAlertResult = true;
    mLastAlertOk = responseCode == 200;
    // Never beep or vibrate about this. The phone may simply not be there, and an
    // alarm app that complains about its own connectivity all night gets switched
    // off - which is a far worse failure than a missed push.
    endRequest(responseCode == 200 ? 0 : responseCode);
    if (responseCode != 200) {
      writeLog("ShakeDetectorPhone", "alert POST failed, code = " + responseCode);
    }
  }

  //! Called once a second. Connect IQ has no per-request timeout, so abandoning a
  //! stuck request is on us - otherwise mRequestInProgress latches and no further
  //! alert is ever sent.
  function onTick() as Void {
    if (!mRequestInProgress) {
      return;
    }
    if (Time.now().value() - mRequestStartSecs >= REQUEST_TIMEOUT_SECS) {
      writeLog("ShakeDetectorPhone.onTick()", "request timed out - cancelling");
      Comm.cancelAllRequests();
      endRequest(Comm.NETWORK_REQUEST_TIMED_OUT);
    }
  }
}
