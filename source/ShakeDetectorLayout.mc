using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
import Toybox.Lang;

// Which alert channels are currently armed, shown as a row of pictograms so the
// state is readable at a glance instead of having to open the menu.
enum {
  ICON_VIBE = 100,
  ICON_SOUND,
  ICON_LIGHT,
  ICON_PHONE,
  ICON_SILENT,
}

// The whole screen layout, for every device. There is deliberately one class and
// no per-shape subclasses: every watch gets the same five things in the same
// order - clock, battery, chart, status, indicator row - and the only thing that
// varies is a handful of fractions.
//
// Instinct-shaped watches (semi-octagon) have a small round sub-window in the top
// right corner, so there the battery goes inside it, the clock shifts left to
// clear it, and the chart starts lower down where the full width is free again.
// That is the entire difference.
//
// Positions are fractions of the real screen size, never fixed pixels, and every
// font is measured rather than assumed - the same code has to land on a 215x180
// ForeRunner and a 176x176 Instinct.
//
// Drawing is restricted to primitives that have been in the API since the 1.x
// days - lines, rectangles, circles. In particular *not* Dc.drawArc: the manifest
// declares minSdkVersion 2.4.0, and on a device without a given method the
// exception aborts the rest of onUpdate(), which silently wipes out everything
// drawn after the offending call.
class ShakeDetectorLayout {
  const ICON_SCALE = 22; // icon size at the 240 px reference height
  const REFERENCE_HEIGHT = 240.0;

  // Shared by every shape.
  const CLOCK_Y_FRACTION = 0.06;
  const STATUS_Y_FRACTION = 0.70;
  const INDICATOR_Y_FRACTION = 0.86;
  const GRAPH_MARGIN_FRACTION = 0.04;
  const GRAPH_STATUS_GAP = 4;

  // Per-shape: clock centre x, battery x/y, chart top, and how much width the
  // clock has to fit into.
  const INSTINCT_CLOCK_X_FRACTION = 0.32;
  const INSTINCT_BATTERY_X_FRACTION = 0.824;
  const INSTINCT_BATTERY_Y_FRACTION = 0.10;
  const INSTINCT_GRAPH_TOP_FRACTION = 0.44;
  const INSTINCT_CLOCK_MAX_WIDTH_FRACTION = 0.59;

  const DEFAULT_CLOCK_X_FRACTION = 0.36;
  const DEFAULT_BATTERY_X_FRACTION = 0.80;
  const DEFAULT_BATTERY_Y_FRACTION = 0.09;
  const DEFAULT_GRAPH_TOP_FRACTION = 0.36;
  const DEFAULT_CLOCK_MAX_WIDTH_FRACTION = 0.70;

  var halfWidth as Number;
  var iconSize as Number;

  var fontClock as Gfx.FontDefinition;
  var fontStatus as Gfx.FontDefinition;

  var xClock as Number;
  var yClock as Number;
  var xBattery as Number;
  var yBattery as Number;
  var yStatusLine as Number;
  var yIndicatorLine as Number;
  var graphX as Number;
  var graphY as Number;
  var graphWidth as Number;
  var graphHeight as Number;

  //! Takes the Dc so it can measure fonts itself - which strings have to fit
  //! where is a layout question, not the view's business.
  function initialize(dc as Gfx.Dc, isInstinctShape as Boolean) {
    var width = dc.getWidth();
    var height = dc.getHeight();
    halfWidth = width / 2;
    iconSize = (height * ICON_SCALE) / 240;
    if (iconSize < 9) {
      iconSize = 9;
    }

    var clockXFraction = DEFAULT_CLOCK_X_FRACTION;
    var batteryXFraction = DEFAULT_BATTERY_X_FRACTION;
    var batteryYFraction = DEFAULT_BATTERY_Y_FRACTION;
    var graphTopFraction = DEFAULT_GRAPH_TOP_FRACTION;
    var clockMaxWidthFraction = DEFAULT_CLOCK_MAX_WIDTH_FRACTION;
    if (isInstinctShape) {
      clockXFraction = INSTINCT_CLOCK_X_FRACTION;
      batteryXFraction = INSTINCT_BATTERY_X_FRACTION;
      batteryYFraction = INSTINCT_BATTERY_Y_FRACTION;
      graphTopFraction = INSTINCT_GRAPH_TOP_FRACTION;
      clockMaxWidthFraction = INSTINCT_CLOCK_MAX_WIDTH_FRACTION;
    }

    xClock = (width * clockXFraction).toNumber();
    yClock = (height * CLOCK_Y_FRACTION).toNumber();
    xBattery = (width * batteryXFraction).toNumber();
    yBattery = (height * batteryYFraction).toNumber();
    yStatusLine = (height * STATUS_Y_FRACTION).toNumber();
    yIndicatorLine = (height * INDICATOR_Y_FRACTION).toNumber();

    graphX = (width * GRAPH_MARGIN_FRACTION).toNumber();
    graphWidth = width - 2 * graphX;
    graphY = (height * graphTopFraction).toNumber();
    graphHeight = yStatusLine - graphY - GRAPH_STATUS_GAP;
    if (graphHeight < 0) {
      graphHeight = 0;
    }

    fontClock = pickFont(
      dc,
      "23:59",
      (width * clockMaxWidthFraction).toNumber(),
      // FONT_NUMBER_* rather than the FONT_SYSTEM_NUMBER_* aliases: the plain
      // names have existed since the 1.x API, and this app declares
      // minSdkVersion 2.4.0.
      [
        Gfx.FONT_NUMBER_HOT,
        Gfx.FONT_NUMBER_MEDIUM,
        Gfx.FONT_NUMBER_MILD,
        Gfx.FONT_LARGE,
        Gfx.FONT_MEDIUM,
      ]
    );
    fontStatus = pickFont(
      dc,
      Ui.loadResource(Rez.Strings.Status_silent).toString(),
      width,
      [Gfx.FONT_LARGE, Gfx.FONT_MEDIUM, Gfx.FONT_SMALL, Gfx.FONT_TINY]
    );
  }

  //! First font in `ladder` (largest first) whose `sample` fits `maxWidth`.
  function pickFont(
    dc as Gfx.Dc,
    sample as String,
    maxWidth as Number,
    ladder as Array<Gfx.FontDefinition>
  ) as Gfx.FontDefinition {
    for (var i = 0; i < ladder.size(); i += 1) {
      if (dc.getTextDimensions(sample, ladder[i])[0] <= maxWidth) {
        return ladder[i];
      }
    }
    return ladder[ladder.size() - 1];
  }

  //! Clock, battery and heart rate. No app name anywhere: on any of these screens
  //! the clock and the chart are worth more than a label naming the app you just
  //! opened.
  function drawHeader(
    dc as Gfx.Dc,
    timeString as String,
    batteryPercent as Float
  ) as Void {
    dc.drawText(xClock, yClock, fontClock, timeString, Gfx.TEXT_JUSTIFY_CENTER);
    dc.drawText(
      xBattery,
      yBattery,
      Gfx.FONT_XTINY,
      batteryPercent.format("%02.0f") + "%",
      Gfx.TEXT_JUSTIFY_CENTER
    );
  }

  function drawStatus(dc as Gfx.Dc, text as String) as Void {
    dc.drawText(halfWidth, yStatusLine, fontStatus, text, Gfx.TEXT_JUSTIFY_CENTER);
  }

  //! Plot the window-total history as a bar chart with the alarm threshold drawn
  //! across it as a dashed line. `trace` is oldest-first; the newest second is at
  //! the right hand edge.
  //!
  //! The y axis is fixed at twice the threshold rather than auto-scaling to the
  //! data, so the threshold line never moves - an auto-scaled chart would make a
  //! quiet wrist look identical to a violent one.
  function drawGraph(dc as Gfx.Dc, trace as Array<Number>, threshold as Number) as Void {
    if (graphHeight <= 0 || threshold <= 0) {
      return;
    }
    var n = trace.size();
    if (n == 0) {
      return;
    }
    var maxValue = threshold * 2;
    var bottom = graphY + graphHeight;

    dc.setPenWidth(1);
    dc.drawLine(graphX, bottom, graphX + graphWidth, bottom);
    var yThreshold = bottom - (graphHeight * threshold) / maxValue;
    for (var x = graphX; x < graphX + graphWidth; x += 8) {
      dc.drawLine(x, yThreshold, x + 4, yThreshold);
    }

    var colWidth = graphWidth / n;
    if (colWidth < 1) {
      colWidth = 1;
    }
    var barWidth = colWidth - 1;
    if (barWidth < 1) {
      barWidth = 1;
    }
    for (var i = 0; i < n; i += 1) {
      var value = trace[i];
      if (value <= 0) {
        continue;
      }
      if (value > maxValue) {
        value = maxValue;
      }
      var barHeight = (graphHeight * value) / maxValue;
      dc.fillRectangle(graphX + i * colWidth, bottom - barHeight, barWidth, barHeight);
    }
  }

  //! Draw the given icons as one centred row along the bottom, below the status.
  function drawIndicators(dc as Gfx.Dc, icons as Array<Number>) as Void {
    var n = icons.size();
    if (n == 0) {
      return;
    }
    var s = iconSize;
    var gap = s / 2;
    var x = halfWidth - (n * s + (n - 1) * gap) / 2;
    var cy = yIndicatorLine + s / 2;
    for (var i = 0; i < n; i += 1) {
      var cx = x + i * (s + gap) + s / 2;
      var icon = icons[i];
      if (icon == ICON_VIBE) {
        drawVibeIcon(dc, cx, cy, s);
      } else if (icon == ICON_SOUND) {
        drawSoundIcon(dc, cx, cy, s);
      } else if (icon == ICON_LIGHT) {
        drawLightIcon(dc, cx, cy, s);
      } else if (icon == ICON_PHONE) {
        drawPhoneIcon(dc, cx, cy, s);
      } else {
        drawSilentIcon(dc, cx, cy, s);
      }
    }
    dc.setPenWidth(1);
  }

  //! A watch body with waves coming off *both* sides.
  function drawVibeIcon(dc as Gfx.Dc, cx as Number, cy as Number, s as Number) as Void {
    dc.setPenWidth(1);
    var bodyW = s / 3;
    var bodyH = (s * 2) / 3;
    // Plain fillRectangle, not fillRoundedRectangle - at this size the rounding
    // is invisible anyway and this keeps to primitives that are certain to exist
    // on a 2.4-era device.
    dc.fillRectangle(cx - bodyW / 2, cy - bodyH / 2, bodyW, bodyH);
    var inner = s / 6;
    var outer = s / 4;
    dc.drawLine(cx - bodyW, cy - inner, cx - bodyW, cy + inner);
    dc.drawLine(cx - s / 2, cy - outer, cx - s / 2, cy + outer);
    dc.drawLine(cx + bodyW, cy - inner, cx + bodyW, cy + inner);
    dc.drawLine(cx + s / 2, cy - outer, cx + s / 2, cy + outer);
  }

  //! A speaker driver with waves coming off one side only - deliberately
  //! different from the vibration glyph, which has waves on both.
  function drawSoundIcon(dc as Gfx.Dc, cx as Number, cy as Number, s as Number) as Void {
    dc.setPenWidth(1);
    dc.fillRectangle(cx - s / 3, cy - s / 4, s / 4, s / 2);
    dc.drawLine(cx + s / 12, cy - s / 6, cx + s / 12, cy + s / 6);
    dc.drawLine(cx + s / 4, cy - s / 3, cx + s / 4, cy + s / 3);
  }

  //! A sun.
  function drawLightIcon(dc as Gfx.Dc, cx as Number, cy as Number, s as Number) as Void {
    dc.setPenWidth(1);
    dc.fillCircle(cx, cy, s / 5);
    var r1 = s / 3;
    var r2 = s / 2;
    dc.drawLine(cx, cy - r1, cx, cy - r2);
    dc.drawLine(cx, cy + r1, cx, cy + r2);
    dc.drawLine(cx - r1, cy, cx - r2, cy);
    dc.drawLine(cx + r1, cy, cx + r2, cy);
    var d1 = (r1 * 7) / 10;
    var d2 = (r2 * 7) / 10;
    dc.drawLine(cx - d1, cy - d1, cx - d2, cy - d2);
    dc.drawLine(cx + d1, cy - d1, cx + d2, cy - d2);
    dc.drawLine(cx - d1, cy + d1, cx - d2, cy + d2);
    dc.drawLine(cx + d1, cy + d1, cx + d2, cy + d2);
  }


  //! A phone: outlined body with a solid bar for the screen, so it reads as a
  //! different object from the solid watch body in the vibration glyph.
  function drawPhoneIcon(dc as Gfx.Dc, cx as Number, cy as Number, s as Number) as Void {
    dc.setPenWidth(1);
    var w = (s * 2) / 5;
    var h = (s * 3) / 4;
    dc.drawRectangle(cx - w / 2, cy - h / 2, w, h);
    dc.fillRectangle(cx - w / 2 + 2, cy - h / 2 + 2, w - 4, h - 6);
  }

  //! The speaker, struck through. Shown when nothing can alert - either muted or
  //! every channel switched off.
  function drawSilentIcon(dc as Gfx.Dc, cx as Number, cy as Number, s as Number) as Void {
    drawSoundIcon(dc, cx, cy, s);
    dc.setPenWidth(2);
    dc.drawLine(cx - s / 2, cy + s / 2, cx + s / 2, cy - s / 2);
    dc.setPenWidth(1);
  }
}
