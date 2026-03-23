import 'dart:ffi';
import 'dart:io' show Platform, Process;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

/// Native DOC_INFO_1W structure for Win32 StartDocPrinterW.
final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDataType;
}

/// Direct Win32 Spooler API (winspool.drv) for sending raw ESC/POS
/// bytes to a printer. No temp files, no PowerShell, no file locks.
///
/// Usage:
/// ```dart
/// final result = Win32RawPrinter.sendRawData('XP-58', escPosBytes);
/// if (!result.success) print(result.error);
/// ```
class Win32RawPrinter {
  Win32RawPrinter._();

  static final _log = Logger('Win32RawPrinter');

  /// Whether this module can be used on the current platform.
  static bool get isSupported => Platform.isWindows;

  // ── DLL + function bindings (resolved once at first access) ──────────

  static late final DynamicLibrary _winspool =
      DynamicLibrary.open('winspool.drv');

  static late final int Function(
          Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>) _openPrinter =
      _winspool.lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>),
          int Function(
              Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>)>('OpenPrinterW');

  static late final int Function(int) _closePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'ClosePrinter');

  static late final int Function(int, int, Pointer<_DocInfo1>)
      _startDocPrinter = _winspool.lookupFunction<
          Int32 Function(IntPtr, Int32, Pointer<_DocInfo1>),
          int Function(int, int, Pointer<_DocInfo1>)>('StartDocPrinterW');

  static late final int Function(int) _endDocPrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'EndDocPrinter');

  static late final int Function(int) _startPagePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'StartPagePrinter');

  static late final int Function(int) _endPagePrinter = _winspool
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'EndPagePrinter');

  static late final int Function(int, Pointer<Void>, int, Pointer<Int32>)
      _writePrinter = _winspool.lookupFunction<
          Int32 Function(IntPtr, Pointer<Void>, Int32, Pointer<Int32>),
          int Function(
              int, Pointer<Void>, int, Pointer<Int32>)>('WritePrinter');

  // ── Public API ───────────────────────────────────────────────────────

  /// Send [data] as a RAW document to the printer identified by
  /// [printerName] — the queue name visible in Windows Settings →
  /// Printers & scanners.
  ///
  /// This is a synchronous Win32 call that queues the job into the
  /// spooler and returns immediately. The spooler handles delivery.
  static ({bool success, String? error}) sendRawData(
    String printerName,
    Uint8List data,
  ) {
    if (!isSupported) {
      return (success: false, error: 'Win32 RAW printing requires Windows');
    }

    _log.info('Sending ${data.length} bytes to "$printerName" via Win32 API');

    final pName = printerName.toNativeUtf16(allocator: calloc);
    final hPrinter = calloc<IntPtr>();

    try {
      // ── 1. Open the printer handle ──
      if (_openPrinter(pName, hPrinter, nullptr) == 0) {
        return (
          success: false,
          error:
              'Cannot open printer "$printerName". Verify the name matches '
              'Windows Settings → Printers & scanners exactly.',
        );
      }

      final handle = hPrinter.value;

      try {
        // ── 2. Start a RAW document ──
        final docInfo = calloc<_DocInfo1>();
        final pDocName = 'Digitex Receipt'.toNativeUtf16(allocator: calloc);
        final pDataType = 'RAW'.toNativeUtf16(allocator: calloc);

        docInfo.ref.pDocName = pDocName;
        docInfo.ref.pOutputFile = nullptr;
        docInfo.ref.pDataType = pDataType;

        try {
          if (_startDocPrinter(handle, 1, docInfo) == 0) {
            return (success: false, error: 'StartDocPrinter failed');
          }

          try {
            // ── 3. Start page ──
            if (_startPagePrinter(handle) == 0) {
              return (success: false, error: 'StartPagePrinter failed');
            }

            try {
              // ── 4. Write raw ESC/POS bytes ──
              final pBuf = calloc<Uint8>(data.length);
              final pWritten = calloc<Int32>();

              try {
                // Copy Dart bytes into native memory
                pBuf.asTypedList(data.length).setAll(0, data);

                if (_writePrinter(
                        handle, pBuf.cast(), data.length, pWritten) ==
                    0) {
                  return (success: false, error: 'WritePrinter failed');
                }

                final written = pWritten.value;
                if (written != data.length) {
                  _log.warning(
                      'WritePrinter: wrote $written of ${data.length} bytes');
                }
              } finally {
                calloc.free(pWritten);
                calloc.free(pBuf);
              }
            } finally {
              _endPagePrinter(handle);
            }
          } finally {
            _endDocPrinter(handle);
          }
        } finally {
          calloc.free(pDocName);
          calloc.free(pDataType);
          calloc.free(docInfo);
        }
      } finally {
        _closePrinter(handle);
      }

      _log.info('RAW print to "$printerName" completed (${data.length} bytes)');
      return (success: true, error: null);
    } catch (e) {
      _log.severe('Win32 RAW print error: $e');
      return (success: false, error: 'Win32 print error: $e');
    } finally {
      calloc.free(hPrinter);
      calloc.free(pName);
    }
  }

  /// Resolve a Windows port name (e.g. "USB001") to the printer queue
  /// name that uses it. Returns `null` if no printer is bound to the port.
  ///
  /// This uses PowerShell for discovery only (not for printing).
  static Future<String?> printerNameForPort(String portName) async {
    if (!isSupported) return null;
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Printer | Where-Object { \$_.PortName -eq "$portName" } '
            '| Select-Object -ExpandProperty Name -First 1',
      ]);
      if (result.exitCode == 0) {
        final name = (result.stdout as String).trim();
        if (name.isNotEmpty) {
          _log.info('Resolved port "$portName" → printer "$name"');
          return name;
        }
      }
    } catch (e) {
      _log.warning('Failed to resolve port "$portName": $e');
    }
    return null;
  }
}
