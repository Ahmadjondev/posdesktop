import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import '../models/printer_config.dart';
import '../utils/tspl_commands.dart';
import '../utils/text_bitmap_renderer.dart';
import 'printer_service.dart';
import 'win32_raw_printer.dart';

/// Sends TSPL commands to a thermal barcode label printer.
/// Reuses the same TCP / USB / CUPS transport as [PrinterService].
class BarcodePrinterService {
  static final _log = Logger('BarcodePrinterService');
  static const _connectTimeout = Duration(seconds: 5);

  final PrinterService _printerService = PrinterService();

  /// Print barcode labels for a list of products.
  ///
  /// Each item in [products] should contain:
  ///   - `name` (String)
  ///   - `code` (String) – used as QR content
  ///   - `price` (String)
  Future<PrintResult> printLabels(
    List<Map<String, dynamic>> products,
    BarcodePrinterConfig config,
  ) async {
    if (!config.isConfigured) {
      return const PrintResult(
        success: false,
        error: 'Shtrix-kod printer sozlanmagan.',
      );
    }

    if (products.isEmpty) {
      return const PrintResult(
        success: false,
        error: 'Chop etish uchun mahsulot tanlanmagan.',
      );
    }

    try {
      // Build TSPL commands for all labels as one batch
      final allBytes = <int>[];
      for (final p in products) {
        final name = (p['name'] as String?) ?? '';
        final code = (p['code'] as String?) ?? '';
        final price = (p['price'] as String?) ?? '';

        // Pre-render Cyrillic-capable text as bitmaps
        final truncName = name.length > 28
            ? '${name.substring(0, 28)}..'
            : name;
        BitmapData? nameBitmap;
        BitmapData? priceBitmap;
        try {
          if (_hasNonAscii(truncName)) {
            nameBitmap = await TextBitmapRenderer.render(
              truncName,
              fontSize: 20,
            );
          }
          if (_hasNonAscii(price)) {
            priceBitmap = await TextBitmapRenderer.render(
              price,
              fontSize: 20,
              bold: true,
            );
          }
        } catch (e) {
          _log.warning('Bitmap text render failed, using TEXT fallback: $e');
        }

        final labelBytes = TsplBuilder.buildLabel(
          labelWidth: config.labelWidth,
          labelHeight: config.labelHeight,
          printSpeed: config.speed,
          printDensity: config.density,
          productName: name,
          productCode: code,
          price: price,
          nameBitmap: nameBitmap,
          priceBitmap: priceBitmap,
        );
        allBytes.addAll(labelBytes);
      }

      final bytes = Uint8List.fromList(allBytes);
      _log.info(
        'Sending ${bytes.length} TSPL bytes for ${products.length} labels',
      );

      return _send(bytes, config);
    } catch (e) {
      _log.severe('Label build error: $e');
      return PrintResult(
        success: false,
        error: 'Yorliq yaratishda xatolik: $e',
      );
    }
  }

  /// Print a test label to verify the barcode printer works.
  Future<PrintResult> printTestLabel(BarcodePrinterConfig config) async {
    return printLabels([
      {
        'name': 'АБВГДЕЁЖЗИЙКЛМН',
        'code': 'TEST-001',
        'price': 'ОПРСТУФХЦЧШЩЪЫЬЭЮЯ',
      },
    ], config);
  }

  static bool _hasNonAscii(String s) => s.runes.any((r) => r > 0x7E);

  /// Test connection (delegates to PrinterService transport checks).
  Future<bool> testConnection(BarcodePrinterConfig config) async {
    // Reuse receipt printer's connection test logic via a temporary PrinterConfig
    final tmpConfig = PrinterConfig(
      name: config.name,
      ip: config.ip,
      port: config.port,
      connectionType: config.connectionType,
      usbMode: config.usbMode,
      cupsPrinterName: config.cupsPrinterName,
      devicePath: config.devicePath,
    );
    return _printerService.testConnection(tmpConfig);
  }

  // ── Transport (mirrors PrinterService) ─────────────────────────────

  Future<PrintResult> _send(Uint8List bytes, BarcodePrinterConfig config) {
    if (config.connectionType == ConnectionType.usb) {
      return _sendViaUsb(bytes, config);
    }
    return _sendViaNetwork(bytes, config);
  }

  Future<PrintResult> _sendViaNetwork(
    Uint8List bytes,
    BarcodePrinterConfig config,
  ) async {
    Socket? socket;
    try {
      _log.info('Connecting to barcode printer ${config.ip}:${config.port}');
      socket = await Socket.connect(
        config.ip,
        config.port,
        timeout: _connectTimeout,
      );
      socket.add(bytes);
      await socket.flush();
      _log.info('TSPL data sent successfully');
      return const PrintResult(success: true);
    } on SocketException catch (e) {
      _log.severe('Barcode printer connection error: $e');
      return PrintResult(
        success: false,
        error: 'Printerga ulanib bo\'lmadi: ${e.message}',
      );
    } catch (e) {
      _log.severe('Unexpected barcode printer error: $e');
      return PrintResult(success: false, error: 'Chop etishda xatolik: $e');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<PrintResult> _sendViaUsb(
    Uint8List bytes,
    BarcodePrinterConfig config,
  ) async {
    if (Platform.isWindows) {
      return _sendViaWin32(bytes, config);
    }
    if (config.usbMode == UsbMode.cups) {
      return _sendViaCupsLpr(bytes, config);
    }
    // Direct device write (Linux / macOS)
    try {
      _log.info(
        'Writing ${bytes.length} bytes to device "${config.devicePath}"',
      );
      final device = File(config.devicePath);
      await device.writeAsBytes(bytes, mode: FileMode.append);
      return const PrintResult(success: true);
    } catch (e) {
      _log.severe('Device write error: $e');
      return PrintResult(success: false, error: 'USB chop etishda xatolik: $e');
    }
  }

  Future<PrintResult> _sendViaWin32(
    Uint8List bytes,
    BarcodePrinterConfig config,
  ) async {
    String? printerName;
    if (config.usbMode == UsbMode.cups && config.cupsPrinterName.isNotEmpty) {
      printerName = config.cupsPrinterName;
    } else if (config.devicePath.isNotEmpty) {
      printerName = await Win32RawPrinter.printerNameForPort(config.devicePath);
      if (printerName == null) {
        return PrintResult(
          success: false,
          error: 'Port "${config.devicePath}" ga ulangan printer topilmadi.',
        );
      }
    }
    if (printerName == null || printerName.isEmpty) {
      return const PrintResult(
        success: false,
        error: 'Printer nomi ko\'rsatilmagan.',
      );
    }

    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final result = Win32RawPrinter.sendRawData(printerName, bytes);
      if (result.success) {
        return const PrintResult(success: true);
      }
      _log.warning(
        'Print attempt $attempt/$maxAttempts failed: ${result.error}',
      );
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      } else {
        return PrintResult(
          success: false,
          error: result.error ?? 'Chop etishda xatolik',
        );
      }
    }
    return const PrintResult(
      success: false,
      error: 'Chop etishda xatolik (barcha urinishlar)',
    );
  }

  Future<PrintResult> _sendViaCupsLpr(
    Uint8List bytes,
    BarcodePrinterConfig config,
  ) async {
    final printerName = config.cupsPrinterName;
    _log.info('Sending ${bytes.length} TSPL bytes via CUPS to "$printerName"');
    final tempFile = File(
      '${Directory.systemTemp.path}/digitex_label_${DateTime.now().millisecondsSinceEpoch}.bin',
    );
    try {
      await tempFile.writeAsBytes(bytes);
      final result = await Process.run('lpr', [
        '-P',
        printerName,
        '-o',
        'raw',
        tempFile.path,
      ]);
      if (result.exitCode != 0) {
        final err = (result.stderr as String).trim();
        _log.severe('lpr failed (exit ${result.exitCode}): $err');
        return PrintResult(success: false, error: 'Chop etishda xatolik: $err');
      }
      _log.info('CUPS barcode print job sent');
      return const PrintResult(success: true);
    } catch (e) {
      _log.severe('CUPS print error: $e');
      return PrintResult(success: false, error: 'CUPS xatolik: $e');
    } finally {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
}
