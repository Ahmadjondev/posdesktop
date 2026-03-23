import 'dart:typed_data';

/// Low-level ESC/POS command builder for thermal receipt printers.
///
/// Builds a byte buffer that can be sent directly to a printer via TCP socket.
/// Supports Cyrillic (CP866) and Latin text for Uzbek/Russian receipts.
class EscPosBuilder {
  final List<int> _buffer = [];
  final int charsPerLine;

  EscPosBuilder({this.charsPerLine = 48});

  Uint8List get bytes => Uint8List.fromList(_buffer);

  // ── Printer commands ──────────────────────────────────────────────────

  /// Initialize printer (reset to defaults).
  EscPosBuilder initialize() {
    _buffer.addAll([0x1B, 0x40]); // ESC @
    return this;
  }

  /// Set character code table.
  /// 0 = CP437, 17 = CP866 (Cyrillic), 46 = CP1251 (Windows Cyrillic).
  EscPosBuilder setCodepage(int n) {
    _buffer.addAll([0x1B, 0x74, n]); // ESC t n
    return this;
  }

  /// Text alignment: 0=left, 1=center, 2=right.
  EscPosBuilder align(Alignment a) {
    _buffer.addAll([0x1B, 0x61, a.index]); // ESC a n
    return this;
  }

  EscPosBuilder alignLeft() => align(Alignment.left);
  EscPosBuilder alignCenter() => align(Alignment.center);
  EscPosBuilder alignRight() => align(Alignment.right);

  /// Toggle bold (emphasized) mode.
  EscPosBuilder bold(bool on) {
    _buffer.addAll([0x1B, 0x45, on ? 1 : 0]); // ESC E n
    return this;
  }

  /// Set character size: 0=normal, 0x11=double width+height.
  EscPosBuilder setSize(CharSize size) {
    _buffer.addAll([0x1D, 0x21, size.value]); // GS ! n
    return this;
  }

  /// Write text encoded in CP866 (Cyrillic-compatible).
  EscPosBuilder text(String s) {
    _buffer.addAll(_encodeCP866(s));
    return this;
  }

  /// Write text followed by a newline.
  EscPosBuilder textLn(String s) {
    text(s);
    _buffer.add(0x0A); // LF
    return this;
  }

  /// Write an empty line.
  EscPosBuilder emptyLine() {
    _buffer.add(0x0A);
    return this;
  }

  /// Print a row with left-aligned and right-aligned text on the same line.
  EscPosBuilder row(String left, String right) {
    final gap = charsPerLine - left.length - right.length;
    if (gap > 0) {
      textLn('$left${' ' * gap}$right');
    } else {
      textLn(left);
      alignRight();
      textLn(right);
      alignLeft();
    }
    return this;
  }

  /// Print a dashed separator line.
  EscPosBuilder separator([String char = '-']) {
    textLn(char * charsPerLine);
    return this;
  }

  /// Feed n lines.
  EscPosBuilder feed(int lines) {
    _buffer.addAll([0x1B, 0x64, lines]); // ESC d n
    return this;
  }

  /// Partial cut.
  EscPosBuilder cut() {
    _buffer.addAll([0x1D, 0x56, 0x01]); // GS V 1
    return this;
  }

  /// Full cut.
  EscPosBuilder fullCut() {
    _buffer.addAll([0x1D, 0x56, 0x00]); // GS V 0
    return this;
  }

  // ── CP866 encoding ────────────────────────────────────────────────────

  /// Encode a string to CP866 bytes.
  /// Handles ASCII, Cyrillic (Russian/Uzbek), and common symbols.
  static List<int> _encodeCP866(String s) {
    final bytes = <int>[];
    for (final rune in s.runes) {
      if (rune < 0x80) {
        // Standard ASCII
        bytes.add(rune);
      } else if (rune >= 0x0410 && rune <= 0x043F) {
        // А-Я (0x0410-0x042F) → 0x80-0x9F
        // а-п (0x0430-0x043F) → 0xA0-0xAF
        bytes.add(rune - 0x0410 + 0x80);
      } else if (rune >= 0x0440 && rune <= 0x044F) {
        // р-я (0x0440-0x044F) → 0xE0-0xEF
        bytes.add(rune - 0x0440 + 0xE0);
      } else if (rune == 0x0401) {
        // Ё → 0xF0
        bytes.add(0xF0);
      } else if (rune == 0x0451) {
        // ё → 0xF1
        bytes.add(0xF1);
      } else if (rune == 0x2018 || rune == 0x2019) {
        // Smart quotes → ASCII apostrophe
        bytes.add(0x27);
      } else if (rune == 0x201C || rune == 0x201D) {
        // Smart double quotes → ASCII double quote
        bytes.add(0x22);
      } else if (rune == 0x2013 || rune == 0x2014) {
        // En/Em dash → hyphen
        bytes.add(0x2D);
      } else {
        // Unknown character → '?'
        bytes.add(0x3F);
      }
    }
    return bytes;
  }

  /// Format a number string with thousand separators for receipt display.
  static String formatMoney(String value) {
    final num = double.tryParse(value) ?? 0;
    if (num == 0) return '0';
    final parts = num.toStringAsFixed(0).split('');
    final result = <String>[];
    for (var i = parts.length - 1, count = 0; i >= 0; i--, count++) {
      if (count > 0 && count % 3 == 0 && parts[i] != '-') {
        result.add(' ');
      }
      result.add(parts[i]);
    }
    return result.reversed.join();
  }
}

enum Alignment { left, center, right }

enum CharSize {
  normal(0x00),
  doubleHeight(0x01),
  doubleWidth(0x10),
  doubleAll(0x11);

  const CharSize(this.value);
  final int value;
}
