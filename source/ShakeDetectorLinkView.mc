using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Communications as Comm;
import Toybox.Lang;

// The setup screen: shows the short code the wearer types into a phone browser.
//
// The code is requested once and then kept: re-requesting on every open was wrong.
// A short link is not consumed by being used - it keeps working - so there is nothing
// to refresh, and asking again just made the screen show a different code each time,
// which reads as a malfunction to anyone who wrote the previous one down.
//
// The server is idempotent per device as well, so even a restart gets the same code
// back. Both halves are needed: one keeps the network quiet, the other keeps the code
// stable.
class ShakeDetectorLinkView extends Ui.View {
  // Content starts below 44% of the height, because that is where Instinct's round
  // sub-window in the top right corner ends. These lines are centred and the URL is
  // wide, so anything higher runs underneath it and gets covered. On round and
  // rectangular screens the space above is simply unused, which costs nothing.
  //
  // There is no explanatory caption above the URL: with a real host name the URL
  // takes two lines, and a third line of prose pushed the code off the bottom of the
  // screen. The URL is self-explanatory - it is a URL - and the code is the part that
  // must be readable.
  const URL_Y_FRACTION = 0.44;
  const MESSAGE_Y_FRACTION = 0.46;

  var mPhone as ShakeDetectorPhone;
  var strWaiting as String;
  var strFailed as String;
  var strNeedsHttps as String;
  var strNoPhone as String;

  function initialize(phone as ShakeDetectorPhone) {
    View.initialize();
    mPhone = phone;
    strWaiting = Ui.loadResource(Rez.Strings.Link_waiting).toString();
    strFailed = Ui.loadResource(Rez.Strings.Link_failed).toString();
    strNeedsHttps = Ui.loadResource(Rez.Strings.Link_needs_https).toString();
    strNoPhone = Ui.loadResource(Rez.Strings.Link_no_phone).toString();
  }

  function onShow() as Void {
    // Only if we do not have one yet. The code is stable - the server returns the
    // same one for this device - so a request per screen open is pure noise.
    if (mPhone.getShortCode() == null) {
      mPhone.requestShortLink();
    }
  }

  //! Driven from the app tick, so the screen fills in when the response lands.
  function onTick() as Void {
    Ui.requestUpdate();
  }

  //! The bare Communications error code is useless on a watch face, so translate
  //! the ones that actually happen during setup into something actionable. -1001 in
  //! particular means the URL is not https, which no amount of retrying will fix.
  function failureMessage() as String {
    if (mPhone.isRequestInProgress()) {
      return strWaiting;
    }
    var code = mPhone.getLastErrorCode();
    if (code == Comm.SECURE_CONNECTION_REQUIRED) {
      return strNeedsHttps;
    }
    if (code == Comm.BLE_CONNECTION_UNAVAILABLE) {
      return strNoPhone;
    }
    if (code == 0) {
      return strFailed;
    }
    return strFailed + " " + code;
  }

  function onUpdate(dc as Gfx.Dc) as Void {
    var width = dc.getWidth();
    var height = dc.getHeight();
    var centreX = width / 2;

    dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
    dc.clear();
    dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);

    var code = mPhone.getShortCode();
    if (code == null) {
      dc.drawText(
        centreX,
        height * MESSAGE_Y_FRACTION,
        Gfx.FONT_SMALL,
        failureMessage(),
        Gfx.TEXT_JUSTIFY_CENTER
      );
      return;
    }

    // URL then code, in the order it has to be typed, with the code biggest because
    // it is the part being read off the screen.
    var afterUrl = drawWrapped(
      dc,
      mPhone.getServerHost() + "/s/",
      centreX,
      (height * URL_Y_FRACTION).toNumber(),
      width - 4
    );
    dc.drawText(centreX, afterUrl + 4, Gfx.FONT_LARGE, code, Gfx.TEXT_JUSTIFY_CENTER);
  }

  //! Draw `text` centred, on two lines if one will not fit, and return the y just
  //! below what was drawn.
  //!
  //! The host name is a build-time constant that nobody will re-check against the
  //! screen width, and a real one ("shakedetector.geminixandroid.com/s/") is far
  //! wider than 176 px at the smallest font - so this measures instead of assuming,
  //! and keeps working whatever the host is changed to.
  function drawWrapped(
    dc as Gfx.Dc,
    text as String,
    centreX as Number,
    y as Number,
    maxWidth as Number
  ) as Number {
    var font = Gfx.FONT_XTINY;
    var lineHeight = dc.getFontHeight(font);
    if (dc.getTextDimensions(text, font)[0] <= maxWidth) {
      dc.drawText(centreX, y, font, text, Gfx.TEXT_JUSTIFY_CENTER);
      return y + lineHeight;
    }
    var split = splitPoint(text);
    dc.drawText(
      centreX,
      y,
      font,
      text.substring(0, split),
      Gfx.TEXT_JUSTIFY_CENTER
    );
    dc.drawText(
      centreX,
      y + lineHeight,
      font,
      text.substring(split, text.length()),
      Gfx.TEXT_JUSTIFY_CENTER
    );
    return y + 2 * lineHeight;
  }

  //! Index to break at: after the dot nearest the middle, so a host splits on a
  //! label boundary rather than mid-word. Falls back to the midpoint.
  function splitPoint(text as String) as Number {
    var length = text.length();
    var middle = length / 2;
    var best = -1;
    for (var i = 1; i < length - 1; i += 1) {
      // substring() is typed as nullable, so compare the other way round.
      if (".".equals(text.substring(i, i + 1))) {
        var candidate = i + 1;
        if (best == -1 || (candidate - middle).abs() < (best - middle).abs()) {
          best = candidate;
        }
      }
    }
    return best == -1 ? middle : best;
  }
}

//! Back or select closes the screen; nothing else to do here.
class ShakeDetectorLinkDelegate extends Ui.BehaviorDelegate {
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
