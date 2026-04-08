import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'tspl_commands.dart';

/// Renders text to monochrome 1-bit bitmaps for TSPL BITMAP command.
///
/// Uses Flutter's [TextPainter] to render with system fonts (full Unicode
/// support including Cyrillic), then converts to 1-bit-per-pixel bitmap
/// suitable for the TSPL BITMAP command.
class TextBitmapRenderer {
  /// Render [text] to a monochrome bitmap.
  ///
  /// The bitmap uses 1 bit per pixel, MSB = leftmost pixel, 1 = black.
  static Future<BitmapData> render(
    String text, {
    double fontSize = 20,
    bool bold = false,
  }) async {
    final style = ui.TextStyle(
      fontSize: fontSize,
      color: const ui.Color(0xFF000000),
      fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
    );

    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(textDirection: ui.TextDirection.ltr, maxLines: 1),
          )
          ..pushStyle(style)
          ..addText(text);

    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final pxW = paragraph.longestLine.ceil();
    final pxH = paragraph.height.ceil();

    if (pxW <= 0 || pxH <= 0) {
      return BitmapData(
        widthBytes: 0,
        pixelWidth: 0,
        height: 0,
        data: Uint8List(0),
      );
    }

    // Render text onto a white canvas
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, pxW.toDouble(), pxH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(paragraph, ui.Offset.zero);

    final picture = recorder.endRecording();
    final image = await picture.toImage(pxW, pxH);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    if (byteData == null) {
      throw Exception('Failed to render text to image');
    }

    // Convert RGBA → 1-bit monochrome (MSB-first, 1 = black, 0 = white)
    final wBytes = (pxW + 7) ~/ 8;
    final bits = Uint8List(wBytes * pxH);

    for (var y = 0; y < pxH; y++) {
      for (var x = 0; x < pxW; x++) {
        final off = (y * pxW + x) * 4;
        final r = byteData.getUint8(off);
        final g = byteData.getUint8(off + 1);
        final b = byteData.getUint8(off + 2);
        // Luminance < 128 → black pixel
        if ((r * 299 + g * 587 + b * 114) < 128000) {
          bits[y * wBytes + x ~/ 8] |= (0x80 >> (x & 7));
        }
      }
    }

    return BitmapData(
      widthBytes: wBytes,
      pixelWidth: pxW,
      height: pxH,
      data: bits,
    );
  }
}
