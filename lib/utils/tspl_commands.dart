import 'dart:convert';
import 'dart:typed_data';

/// Builds TSPL/TSPL2 command sequences for thermal label printers
/// such as the Xprinter XP-365B / XP-370B.
///
/// Cyrillic text is rendered as host-side bitmaps via [BitmapData] and sent
/// using the TSPL BITMAP command, because the XP-370B built-in fonts lack
/// Cyrillic glyphs. ASCII-only text uses the TEXT command with built-in fonts.
/// Barcode content is always ASCII.
class TsplBuilder {
  final List<int> _buffer = [];

  /// Raw byte output.
  Uint8List get bytes => Uint8List.fromList(_buffer);

  // ── Setup commands ─────────────────────────────────────────────────

  /// Set label size in mm.
  void size(int widthMm, int heightMm) =>
      _cmd('SIZE $widthMm mm, $heightMm mm');

  /// Set gap between labels in mm.
  void gap(int gapMm, [int offsetMm = 0]) =>
      _cmd('GAP $gapMm mm, $offsetMm mm');

  /// Print speed (1-10).
  void speed(int s) => _cmd('SPEED $s');

  /// Print density (0-15).
  void density(int d) => _cmd('DENSITY $d');

  /// Set print direction. 0 = normal, 1 = mirrored.
  void direction(int dir, [int mirror = 0]) => _cmd('DIRECTION $dir,$mirror');

  /// Clear image buffer.
  void cls() => _cmd('CLS');

  /// Set codepage for text rendering.
  void codepage(String cp) => _cmd('CODEPAGE $cp');

  // ── Content commands ───────────────────────────────────────────────

  /// Print a text string at position (x, y) in dots (203 dpi: 1mm ≈ 8 dots).
  ///
  /// [font] – built-in font name, e.g. "3" (24×24) or "TSS24.BF2" for CJK.
  /// [rotation] – 0, 90, 180, 270.
  /// [xMul], [yMul] – horizontal/vertical magnification (1-10).
  void text(
    int x,
    int y,
    String font,
    int rotation,
    int xMul,
    int yMul,
    String content,
  ) {
    // Build command header as ASCII, encode content as Windows-1251
    final header = 'TEXT $x,$y,"$font",$rotation,$xMul,$yMul,"';
    _buffer.addAll(utf8.encode(header));
    _buffer.addAll(_encodeWin1251(content));
    _buffer.addAll(utf8.encode('"\r\n'));
  }

  /// Print a 1D barcode at position (x, y).
  ///
  /// [codeType] – barcode symbology: "128", "EAN13", "39", etc.
  /// [height] – barcode bar height in dots.
  /// [readable] – 0 = no text, 1 = align left, 2 = center, 3 = align right.
  /// [rotation] – 0, 90, 180, 270.
  /// [narrow] – width of narrow bar in dots (1-10).
  /// [wide] – width of wide bar in dots (1-10).
  void barcode(
    int x,
    int y,
    String codeType,
    int height,
    int readable,
    int rotation,
    int narrow,
    int wide,
    String content,
  ) {
    final escaped = content.replaceAll('"', '\\"');
    _cmd(
      'BARCODE $x,$y,"$codeType",$height,$readable,$rotation,$narrow,$wide,"$escaped"',
    );
  }

  /// Draw a bar (filled rectangle) at position (x, y) with given size.
  void bar(int x, int y, int width, int height) =>
      _cmd('BAR $x,$y,$width,$height');

  /// Send raw monochrome bitmap at position (x, y).
  ///
  /// [widthBytes] – image width in bytes (8 pixels per byte).
  /// [height] – image height in dots.
  /// [data] – raw 1-bit/pixel bitmap, MSB = leftmost, 1 = black.
  void bitmap(int x, int y, int widthBytes, int height, Uint8List data) {
    final header = 'BITMAP $x,$y,$widthBytes,$height,0,';
    _buffer.addAll(utf8.encode(header));
    _buffer.addAll(data);
    _buffer.addAll([0x0D, 0x0A]);
  }

  // ── Print commands ─────────────────────────────────────────────────

  /// Print labels. [sets] = number of label sets, [copies] = copies per set.
  void print(int sets, [int copies = 1]) => _cmd('PRINT $sets,$copies');

  // ── Helpers ────────────────────────────────────────────────────────

  void _cmd(String command) {
    _buffer.addAll(utf8.encode('$command\r\n'));
  }

  /// Encode a string to Windows-1251 bytes for Cyrillic label text.
  static List<int> _encodeWin1251(String s) {
    final bytes = <int>[];
    for (final rune in s.runes) {
      if (rune < 0x80) {
        bytes.add(rune);
      } else if (rune >= 0x0410 && rune <= 0x042F) {
        // А-Я → 0xC0-0xDF
        bytes.add(rune - 0x0410 + 0xC0);
      } else if (rune >= 0x0430 && rune <= 0x044F) {
        // а-я → 0xE0-0xFF
        bytes.add(rune - 0x0430 + 0xE0);
      } else if (rune == 0x0401) {
        // Ё → 0xA8
        bytes.add(0xA8);
      } else if (rune == 0x0451) {
        // ё → 0xB8
        bytes.add(0xB8);
      } else if (rune == 0x040E) {
        // Ў → 0xA1
        bytes.add(0xA1);
      } else if (rune == 0x045E) {
        // ў → 0xA2
        bytes.add(0xA2);
      } else if (rune == 0x0490) {
        // Ґ → 0xA5
        bytes.add(0xA5);
      } else if (rune == 0x0491) {
        // ґ → 0xB4
        bytes.add(0xB4);
      } else if (rune == 0x0404) {
        // Є → 0xAA
        bytes.add(0xAA);
      } else if (rune == 0x0454) {
        // є → 0xBA
        bytes.add(0xBA);
      } else if (rune == 0x0406) {
        // І → 0xB2
        bytes.add(0xB2);
      } else if (rune == 0x0456) {
        // і → 0xB3
        bytes.add(0xB3);
      } else if (rune == 0x0407) {
        // Ї → 0xAF
        bytes.add(0xAF);
      } else if (rune == 0x0457) {
        // ї → 0xBF
        bytes.add(0xBF);
      } else if (rune == 0x2116) {
        // № → 0xB9
        bytes.add(0xB9);
      } else {
        bytes.add(0x3F); // Unknown → '?'
      }
    }
    return bytes;
  }

  /// Build TSPL commands for a single 57×40mm CODE128 barcode label.
  ///
  /// Layout (57mm × 40mm at 203dpi → 456×320 dots):
  ///   - Product name (top, centered)        ~24 dots high
  ///   - CODE128 barcode (center)             ~80 dots high
  ///   - Product code (below barcode)         ~24 dots high
  ///   - Price (bottom, centered)             ~24 dots high
  ///
  /// Total content height ≈ 24 + 8 + 80 + 8 + 24 + 8 + 24 = 176 dots.
  /// Available height = 320 dots. Top offset ≈ (320 - 176) / 2 = 72 dots.
  static Uint8List buildLabel({
    required int labelWidth,
    required int labelHeight,
    required int printSpeed,
    required int printDensity,
    required String productName,
    required String productCode,
    required String price,
    BitmapData? nameBitmap,
    BitmapData? priceBitmap,
  }) {
    final b = TsplBuilder()
      ..size(labelWidth, labelHeight)
      ..gap(2)
      ..speed(printSpeed)
      ..density(printDensity)
      ..direction(1)
      ..cls();

    // Convert mm to dots (203 dpi ≈ 8 dots/mm)
    final widthDots = labelWidth * 8;
    final heightDots = labelHeight * 8;

    // Element heights – use actual bitmap height when available
    final nameH = nameBitmap?.height ?? 24;
    const barcodeH = 80;
    const codeH = 24; // font "3" height (ASCII product code)
    final priceH = priceBitmap?.height ?? 24;
    const gap = 8; // spacing between elements

    // Total content block height
    final contentH = nameH + gap + barcodeH + gap + codeH + gap + priceH;
    // Vertical offset to center the block
    final topY = ((heightDots - contentH) / 2)
        .clamp(4, heightDots ~/ 4)
        .toInt();

    // ── Product name at top ──
    if (nameBitmap != null && nameBitmap.height > 0) {
      final nameX = ((widthDots - nameBitmap.pixelWidth) / 2)
          .clamp(4, widthDots)
          .toInt();
      b.bitmap(
        nameX,
        topY,
        nameBitmap.widthBytes,
        nameBitmap.height,
        nameBitmap.data,
      );
    } else {
      final name = productName.length > 28
          ? '${productName.substring(0, 26)}..'
          : productName;
      final nameWidth = name.length * 12;
      final nameX = ((widthDots - nameWidth) / 2).clamp(4, widthDots).toInt();
      b.text(nameX, topY, '3', 0, 1, 1, name);
    }

    // ── CODE128 barcode in center ──
    final barcodeNarrow = 2;
    // Estimate barcode width: CODE128 ≈ (11 * chars + 35) * narrow dots
    final barcodeEstWidth = (11 * productCode.length + 35) * barcodeNarrow;
    final barcodeX = ((widthDots - barcodeEstWidth) / 2)
        .clamp(24, widthDots)
        .toInt();
    final barcodeY = topY + nameH + gap;
    // readable = 0 (we render our own text below for better positioning)
    b.barcode(
      barcodeX,
      barcodeY,
      '128',
      barcodeH,
      0,
      0,
      barcodeNarrow,
      barcodeNarrow,
      productCode,
    );

    // ── Product code below barcode ──
    final codeWidth = productCode.length * 12;
    final codeX = ((widthDots - codeWidth) / 2).clamp(4, widthDots).toInt();
    final codeY = barcodeY + barcodeH + gap;
    b.text(codeX, codeY, '3', 0, 1, 1, productCode);

    // ── Price at bottom ──
    final priceY = codeY + codeH + gap;
    if (priceBitmap != null && priceBitmap.height > 0) {
      final priceX = ((widthDots - priceBitmap.pixelWidth) / 2)
          .clamp(4, widthDots)
          .toInt();
      b.bitmap(
        priceX,
        priceY,
        priceBitmap.widthBytes,
        priceBitmap.height,
        priceBitmap.data,
      );
    } else {
      final priceWidth = price.length * 16;
      final priceX = ((widthDots - priceWidth) / 2).clamp(4, widthDots).toInt();
      b.text(priceX, priceY, '4', 0, 1, 1, price);
    }

    b.print(1);

    return b.bytes;
  }
}

/// Monochrome bitmap data for the TSPL BITMAP command.
class BitmapData {
  final int widthBytes;
  final int pixelWidth;
  final int height;
  final Uint8List data;

  const BitmapData({
    required this.widthBytes,
    required this.pixelWidth,
    required this.height,
    required this.data,
  });
}
