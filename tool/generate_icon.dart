import 'dart:io';
import 'dart:math';

import 'package:image/image.dart';

void main() {
  const size = 1024;
  final img = Image(width: size, height: size);

  // Background colors: subtle indigo gradient
  const bgTopR = 57, bgTopG = 73, bgTopB = 171; // #3949AB (Indigo 600)
  const bgBotR = 26, bgBotG = 35, bgBotB = 126; // #1A237E (Indigo 900)

  // Shield dimensions
  const centerX = 512.0;
  const topY = 190.0;
  const sideY = 230.0;
  const straightBottomY = 480.0;
  const tipY = 820.0;
  const maxHalfWidth = 236.0;

  // Clock dimensions
  const clockCenterX = 512.0;
  const clockCenterY = 470.0;
  const clockOuterRadius = 142.0;
  const clockInnerRadius = 114.0;
  const clockHubRadius = 18.0;
  const handHalfWidth = 10.0;
  const hourHandLength = 85.0; // upwards to y = 385
  const minuteHandLength = 80.0; // rightwards to x = 592

  bool isInsideShield(double x, double y) {
    if (y < topY || y > tipY) return false;
    final dx = (x - centerX).abs();

    if (y < sideY) {
      // Top gentle arched crest
      final t = dx / maxHalfWidth;
      if (t > 1.0) return false;
      final crestY = topY + (sideY - topY) * (t * t);
      return y >= crestY;
    } else if (y <= straightBottomY) {
      // Straight vertical sides
      return dx <= maxHalfWidth;
    } else {
      // Smooth curve tapering down to tip
      final progress = (y - straightBottomY) / (tipY - straightBottomY);
      final hw = maxHalfWidth * (1.0 - pow(progress, 1.45));
      return dx <= hw;
    }
  }

  bool isClockGlyph(double x, double y) {
    final dx = x - clockCenterX;
    final dy = y - clockCenterY;
    final distSq = dx * dx + dy * dy;
    final dist = sqrt(distSq);

    // Outer clock ring
    if (dist >= clockInnerRadius && dist <= clockOuterRadius) {
      return true;
    }

    // Center hub
    if (dist <= clockHubRadius) {
      return true;
    }

    // Hour hand: pointing up (12 o'clock)
    if (dy <= 0 && dy >= -hourHandLength && dx.abs() <= handHalfWidth) {
      return true;
    }
    // Hour hand rounded tip
    final hourTipDist = sqrt(
      dx * dx + (dy + hourHandLength) * (dy + hourHandLength),
    );
    if (hourTipDist <= handHalfWidth) {
      return true;
    }

    // Minute hand: pointing right (3 o'clock)
    if (dx >= 0 && dx <= minuteHandLength && dy.abs() <= handHalfWidth) {
      return true;
    }
    // Minute hand rounded tip
    final minTipDist = sqrt(
      (dx - minuteHandLength) * (dx - minuteHandLength) + dy * dy,
    );
    if (minTipDist <= handHalfWidth) {
      return true;
    }

    // 12 o'clock tick marker
    if (dx.abs() <= 5.0 &&
        dy <= -clockInnerRadius &&
        dy >= -clockInnerRadius - 14.0) {
      return true;
    }
    // 6 o'clock tick marker
    if (dx.abs() <= 5.0 &&
        dy >= clockInnerRadius - 14.0 &&
        dy <= clockInnerRadius) {
      return true;
    }
    // 9 o'clock tick marker
    if (dy.abs() <= 5.0 &&
        dx <= -clockInnerRadius &&
        dx >= -clockInnerRadius - 14.0) {
      return true;
    }

    return false;
  }

  // 2x2 supersampling for smooth antialiased edges
  const subOffsets = [0.25, 0.75];

  for (var py = 0; py < size; py++) {
    final tY = py / size;
    final bgR = (bgTopR + (bgBotR - bgTopR) * tY).round();
    final bgG = (bgTopG + (bgBotG - bgTopG) * tY).round();
    final bgB = (bgTopB + (bgBotB - bgTopB) * tY).round();

    for (var px = 0; px < size; px++) {
      var rSum = 0;
      var gSum = 0;
      var bSum = 0;

      for (final oy in subOffsets) {
        for (final ox in subOffsets) {
          final x = px + ox;
          final y = py + oy;

          if (isInsideShield(x, y)) {
            if (isClockGlyph(x, y)) {
              // Clock glyph inside shield (uses background indigo color for contrast)
              rSum += bgR;
              gSum += bgG;
              bSum += bgB;
            } else {
              // Shield white fill
              rSum += 255;
              gSum += 255;
              bSum += 255;
            }
          } else {
            // Background indigo
            rSum += bgR;
            gSum += bgG;
            bSum += bgB;
          }
        }
      }

      final r = (rSum / 4).round();
      final g = (gSum / 4).round();
      final b = (bSum / 4).round();

      img.setPixelRgba(px, py, r, g, b, 255);
    }
  }

  final pngBytes = encodePng(img);
  final outFile = File('assets/icon/app_icon.png');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsBytesSync(pngBytes);
  stdout.writeln(
    'Successfully generated ${outFile.path} (${pngBytes.length} bytes)',
  );
}
