import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import '../models/printer_config.dart';
import '../models/receipt_data.dart';
import '../utils/esc_pos_commands.dart';

/// Sends ESC/POS commands to a thermal printer via TCP socket or USB.
class PrinterService {
  static final _log = Logger('PrinterService');
  static const _connectTimeout = Duration(seconds: 5);

  /// Discover USB print ports registered with the Windows USB Monitor
  /// (e.g. USB001, USB002). Returns an empty list on non-Windows.
  Future<List<String>> listWindowsUsbPorts() async {
    if (!Platform.isWindows) return [];
    try {
      final result = await Process.run('powershell', [
        '-Command',
        r"Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Print\Monitors\USB Monitor\Ports\*' -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }",
      ]);
      if (result.exitCode != 0) {
        _log.warning('USB Monitor registry query failed: ${result.stderr}');
        return [];
      }
      return (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList()
        ..sort();
    } catch (e) {
      _log.warning('Failed to list Windows USB ports: $e');
      return [];
    }
  }

  /// Discover printers registered in CUPS (macOS/Linux) or Windows spooler.
  Future<List<String>> listCupsPrinters() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-Printer | Select-Object -ExpandProperty Name',
        ]);
        if (result.exitCode != 0) {
          _log.warning('Get-Printer failed: ${result.stderr}');
          return [];
        }
        return (result.stdout as String)
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .toList()
          ..sort();
      } else {
        // macOS / Linux — use lpstat
        final result = await Process.run('lpstat', ['-a']);
        print(result.stdout);
        print(result.stderr);
        print(result.exitCode);
        print(result.pid);
        if (result.exitCode != 0) {
          _log.warning('lpstat failed: ${result.stderr}');
          return [];
        }
        // Lines: "PrinterName accepting requests since ..."
        return (result.stdout as String)
            .split('\n')
            .where((l) => l.isNotEmpty)
            .map((l) => l.split(' ').first)
            .toList()
          ..sort();
      }
    } catch (e) {
      _log.warning('Failed to list printers: $e');
      return [];
    }
  }

  /// Test if the printer is reachable.
  Future<bool> testConnection(PrinterConfig config) async {
    if (config.connectionType == ConnectionType.usb) {
      return _testUsb(config);
    }
    return _testNetwork(config);
  }

  Future<bool> _testNetwork(PrinterConfig config) async {
    try {
      _log.info('Testing connection to ${config.ip}:${config.port}');
      final socket = await Socket.connect(
        config.ip,
        config.port,
        timeout: _connectTimeout,
      );
      await socket.close();
      _log.info('Connection test successful');
      return true;
    } on SocketException catch (e) {
      _log.warning('Connection test failed: $e');
      return false;
    }
  }

  Future<bool> _testUsb(PrinterConfig config) async {
    try {
      if (config.usbMode == UsbMode.cups) {
        final printers = await listCupsPrinters();
        final found = printers.contains(config.cupsPrinterName);
        _log.info(
          'CUPS test: "${config.cupsPrinterName}" ${found ? "found" : "not found"} in $printers',
        );
        return found;
      } else {
        if (Platform.isWindows) {
          // COM/LPT ports can't be tested with File.existsSync on Windows
          final result = await Process.run('cmd', [
            '/c',
            'mode',
            config.devicePath,
          ]);
          final ok = result.exitCode == 0;
          _log.info('Device port test: "${config.devicePath}" ok=$ok');
          return ok;
        }
        final exists = File(config.devicePath).existsSync();
        _log.info('Device path test: "${config.devicePath}" exists=$exists');
        return exists;
      }
    } catch (e) {
      _log.warning('USB test failed: $e');
      return false;
    }
  }

  /// Print a receipt to the configured thermal printer.
  Future<PrintResult> printReceipt(
    ReceiptData receipt,
    PrinterConfig config,
  ) async {
    final bytes = _buildReceiptBytes(receipt, config);
    return _send(bytes, config);
  }

  /// Print a test page to verify the printer works.
  Future<PrintResult> printTestPage(PrinterConfig config) async {
    final builder = EscPosBuilder(charsPerLine: config.charsPerLine)
      ..initialize()
      ..setCodepage(config.codepage)
      ..alignCenter()
      ..bold(true)
      ..setSize(CharSize.doubleAll)
      ..textLn('DIGITEX POS')
      ..setSize(CharSize.normal)
      ..bold(false)
      ..emptyLine()
      ..textLn('Printer Test Page')
      ..emptyLine()
      ..alignLeft()
      ..separator()
      ..row('Printer:', config.name);

    if (config.connectionType == ConnectionType.network) {
      builder.row('IP:', '${config.ip}:${config.port}');
    } else if (config.usbMode == UsbMode.cups) {
      builder.row('CUPS:', config.cupsPrinterName);
    } else {
      builder.row('Device:', config.devicePath);
    }

    builder
      ..row(
        'Mode:',
        config.connectionType == ConnectionType.network ? 'Network' : 'USB',
      )
      ..row('Paper:', config.paperWidth == PaperWidth.mm57 ? '57mm' : '80mm')
      ..row(
        'Codepage:',
        'CP${config.codepage == 17 ? "866" : config.codepage.toString()}',
      )
      ..separator()
      ..emptyLine()
      ..textLn('Latin: ABCDEFGabcdefg 0123456789')
      ..textLn('Cyrillic: АБВГДЕЖЗабвгдежз')
      ..textLn('Symbols: @#\$%&*()+-=[]{}')
      ..emptyLine()
      ..separator()
      ..alignCenter()
      ..textLn('Test completed successfully!')
      ..emptyLine()
      ..textLn(DateTime.now().toString().substring(0, 19))
      ..feed(4)
      ..cut();

    return _send(builder.bytes, config);
  }

  /// Route to the correct transport.
  Future<PrintResult> _send(Uint8List bytes, PrinterConfig config) {
    if (config.connectionType == ConnectionType.usb) {
      return _sendViaUsb(bytes, config);
    }
    return _sendToprinter(bytes, config);
  }

  // ── Private ───────────────────────────────────────────────────────────

  Uint8List _buildReceiptBytes(ReceiptData receipt, PrinterConfig config) {
    final b = EscPosBuilder(charsPerLine: config.charsPerLine);
    final fmt = EscPosBuilder.formatMoney;

    b
      ..initialize()
      ..setCodepage(config.codepage);

    // ── Header ──
    b
      ..alignCenter()
      ..bold(true)
      ..setSize(CharSize.doubleAll)
      ..textLn('DIGITEX POS')
      ..setSize(CharSize.normal)
      ..bold(false)
      ..emptyLine();

    // ── Sale info ──
    b
      ..alignLeft()
      ..row('Chek:', receipt.saleNumber)
      ..row('Sana:', _formatDate(receipt.date))
      ..row('Kassir:', receipt.cashier);

    if (receipt.customerName != null) {
      b.row('Mijoz:', receipt.customerName!);
    }
    if (receipt.customerPhone != null) {
      b.row('Tel:', receipt.customerPhone!);
    }

    b.separator('=');

    // ── Items header ──
    if (config.charsPerLine >= 48) {
      // 80mm: Name(22) Qty(5) Price(10) Total(11)
      b
        ..bold(true)
        ..textLn(
          '${'Nomi'.padRight(22)}${'Soni'.padLeft(5)}${'Narxi'.padLeft(10)}${'Jami'.padLeft(11)}',
        )
        ..bold(false)
        ..separator('-');
    } else {
      // 57mm: two-line layout
      b
        ..bold(true)
        ..textLn('Nomi / Soni x Narxi = Jami')
        ..bold(false)
        ..separator('-');
    }

    // ── Items ──
    for (final item in receipt.items) {
      final qty = _formatQty(item.quantity);
      final price = fmt(item.price);
      final total = fmt(item.total);

      if (config.charsPerLine >= 48) {
        // Truncate name to fit
        final name = item.name.length > 22
            ? item.name.substring(0, 22)
            : item.name.padRight(22);
        b.textLn(
          '$name${qty.padLeft(5)}${price.padLeft(10)}${total.padLeft(11)}',
        );
      } else {
        b
          ..textLn(item.name)
          ..row('  $qty x $price', total);
      }
    }

    b.separator('=');

    // ── Totals ──
    b.row('Jami:', '${fmt(receipt.subtotalUzs)} UZS');

    final discount = double.tryParse(receipt.discountUzs) ?? 0;
    if (discount > 0) {
      b.row('Chegirma:', '-${fmt(receipt.discountUzs)} UZS');
    }

    b
      ..separator('-')
      ..bold(true)
      ..setSize(CharSize.doubleHeight)
      ..row('ITOGO:', '${fmt(receipt.totalUzs)} UZS')
      ..setSize(CharSize.normal)
      ..bold(false)
      ..separator('-');

    // ── Payments ──
    for (final p in receipt.payments) {
      b.row(p.method, '${fmt(p.amount)} UZS');
    }

    final changeDue = double.tryParse(receipt.changeDueUzs) ?? 0;
    if (changeDue > 0) {
      b.row('Qaytim:', '${fmt(receipt.changeDueUzs)} UZS');
    }

    // ── Balance info ──
    final balanceApplied = double.tryParse(receipt.balanceAppliedUzs) ?? 0;
    final balanceCredited = double.tryParse(receipt.balanceCreditedUzs) ?? 0;

    if (balanceApplied > 0 || balanceCredited > 0) {
      b.separator('-');
      if (balanceApplied > 0) {
        b.row('Balansdan:', '-${fmt(receipt.balanceAppliedUzs)} UZS');
      }
      if (balanceCredited > 0) {
        b.row('Balansga:', '+${fmt(receipt.balanceCreditedUzs)} UZS');
      }
    }

    // ── Customer debt ──
    if (receipt.customerBalance != null) {
      final debt = double.tryParse(receipt.customerBalance!.debtUzs) ?? 0;
      if (debt > 0) {
        b
          ..separator('-')
          ..bold(true)
          ..row('Qarz:', '${fmt(receipt.customerBalance!.debtUzs)} UZS')
          ..bold(false);
      }
    }

    // ── Footer ──
    b
      ..emptyLine()
      ..separator('-')
      ..alignCenter()
      ..textLn('Xaridingiz uchun rahmat!')
      ..textLn('Thank you for your purchase!')
      ..emptyLine()
      ..textLn('digitex.uz')
      ..feed(4)
      ..cut();

    return b.bytes;
  }

  Future<PrintResult> _sendToprinter(
    Uint8List bytes,
    PrinterConfig config,
  ) async {
    Socket? socket;
    try {
      _log.info(
        'Connecting to printer ${config.ip}:${config.port} (${bytes.length} bytes)',
      );

      socket = await Socket.connect(
        config.ip,
        config.port,
        timeout: _connectTimeout,
      );

      socket.add(bytes);
      await socket.flush();
      _log.info('Receipt sent successfully');

      return const PrintResult(success: true);
    } on SocketException catch (e) {
      _log.severe('Printer connection error: $e');
      return PrintResult(
        success: false,
        error: 'Printerga ulanib bo\'lmadi: ${e.message}',
      );
    } catch (e) {
      _log.severe('Unexpected printer error: $e');
      return PrintResult(success: false, error: 'Chop etishda xatolik: $e');
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  Future<PrintResult> _sendViaUsb(Uint8List bytes, PrinterConfig config) async {
    final tempFile = File(
      '${Directory.systemTemp.path}/digitex_receipt_${DateTime.now().millisecondsSinceEpoch}.bin',
    );

    try {
      await tempFile.writeAsBytes(bytes);

      if (config.usbMode == UsbMode.cups) {
        // Print via CUPS (lpr) on macOS/Linux, or lpr/powershell on Windows
        final printerName = config.cupsPrinterName;
        _log.info('Sending ${bytes.length} bytes via CUPS to "$printerName"');

        if (Platform.isWindows) {
          // Windows: use Win32 Spooler API (OpenPrinter/WritePrinter) for raw ESC/POS.
          // \\localhost\PrinterName requires the printer to be shared — use API instead.
          return await _sendViaWindowsSpooler(printerName, tempFile);
        }
        // macOS / Linux
        final result = await Process.run('lpr', [
          '-P',
          printerName,
          '-o',
          'raw',
          tempFile.path,
        ]);

        if (result.exitCode != 0) {
          final err = (result.stderr as String).trim();
          _log.severe('Print failed (exit ${result.exitCode}): $err');
          return PrintResult(
            success: false,
            error: 'Chop etishda xatolik: $err',
          );
        }

        _log.info('Print job sent successfully');
        return const PrintResult(success: true);
      } else {
        // Direct file/device write
        _log.info(
          'Sending ${bytes.length} bytes to device "${config.devicePath}"',
        );

        if (Platform.isWindows) {
          // Windows: use copy /b to write to port (e.g., COM3, USB001)
          // Normalize: strip leading \\.\  prefix if present
          var portName = config.devicePath;
          if (portName.startsWith(r'\\.\')) {
            portName = portName.substring(4);
          }
          final result = await Process.run('cmd', [
            '/c',
            'copy',
            '/b',
            tempFile.path,
            portName,
          ]);
          if (result.exitCode != 0) {
            final err = (result.stderr as String).trim();
            _log.severe('copy failed: $err');
            return PrintResult(
              success: false,
              error: 'Qurilmaga yozishda xatolik: $err',
            );
          }
        } else {
          // macOS / Linux: write directly to device file
          final device = File(config.devicePath);
          await device.writeAsBytes(bytes, mode: FileMode.append);
        }

        _log.info('Device write successful');
        return const PrintResult(success: true);
      }
    } catch (e) {
      _log.severe('USB print error: $e');
      return PrintResult(success: false, error: 'USB chop etishda xatolik: $e');
    } finally {
      try {
        if (tempFile.existsSync()) tempFile.deleteSync();
      } catch (_) {}
    }
  }

  /// Send raw bytes to a locally-installed Windows printer via Win32 Spooler API.
  /// Uses a PowerShell inline C# P/Invoke script so no external tools or
  /// printer sharing are required.
  Future<PrintResult> _sendViaWindowsSpooler(
    String printerName,
    File dataFile,
  ) async {
    File? psFile;
    try {
      psFile = File(
        '${Directory.systemTemp.path}/dp_${DateTime.now().millisecondsSinceEpoch}.ps1',
      );
      await psFile.writeAsString(
        _buildWindowsRawPrintScript(dataFile.path, printerName),
      );
      final result = await Process.run('powershell', [
        '-ExecutionPolicy',
        'Bypass',
        '-NonInteractive',
        '-File',
        psFile.path,
      ]);
      if (result.exitCode != 0) {
        final err = ((result.stderr as String?) ?? '').trim();
        _log.severe('Windows spooler failed (${result.exitCode}): $err');
        return PrintResult(
          success: false,
          error: 'Windows chop etishda xatolik: $err',
        );
      }
      _log.info('Windows raw print successful');
      return const PrintResult(success: true);
    } catch (e) {
      _log.severe('Windows spooler error: $e');
      return PrintResult(success: false, error: 'Chop etishda xatolik: $e');
    } finally {
      try {
        psFile?.deleteSync();
      } catch (_) {}
    }
  }

  /// Builds a PowerShell script that uses winspool.drv P/Invoke to deliver
  /// raw ESC/POS bytes directly to the Windows print spooler.
  String _buildWindowsRawPrintScript(String filePath, String printerName) {
    // Escape single quotes for PowerShell single-quoted string literals
    final psPath = filePath.replaceAll("'", "''");
    final psName = printerName.replaceAll("'", "''");
    return r"""$ErrorActionPreference = "Stop"
$bytes = [System.IO.File]::ReadAllBytes('""" +
        psPath +
        r"""')
$printerName = '""" +
        psName +
        r"""'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
public class DocInfo {
    [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
}
public class RawPrint {
    [DllImport("winspool.drv", CharSet=CharSet.Auto, SetLastError=true)]
    public static extern bool OpenPrinter(string n, out IntPtr h, IntPtr d);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool ClosePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern int StartDocPrinter(IntPtr h, int l, [In, MarshalAs(UnmanagedType.LPStruct)] DocInfo di);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndDocPrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool StartPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool EndPagePrinter(IntPtr h);
    [DllImport("winspool.drv", SetLastError=true)]
    public static extern bool WritePrinter(IntPtr h, IntPtr p, int n, out int w);
}
"@

$h = [IntPtr]::Zero
if (-not [RawPrint]::OpenPrinter($printerName, [ref]$h, [IntPtr]::Zero)) {
    throw "Cannot open printer: $printerName"
}
try {
    $di = New-Object DocInfo
    $di.pDocName = "Digitex Receipt"
    $di.pDataType = "RAW"
    if ([RawPrint]::StartDocPrinter($h, 1, $di) -eq 0) { throw "StartDocPrinter failed" }
    [RawPrint]::StartPagePrinter($h) | Out-Null
    $ptr = [Runtime.InteropServices.Marshal]::AllocHGlobal($bytes.Length)
    try {
        [Runtime.InteropServices.Marshal]::Copy($bytes, 0, $ptr, $bytes.Length)
        $written = 0
        if (-not [RawPrint]::WritePrinter($h, $ptr, $bytes.Length, [ref]$written)) { throw "WritePrinter failed" }
    } finally {
        [Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
    [RawPrint]::EndPagePrinter($h) | Out-Null
    [RawPrint]::EndDocPrinter($h) | Out-Null
} finally {
    [RawPrint]::ClosePrinter($h) | Out-Null
}
""";
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')}.'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatQty(String qty) {
    final n = double.tryParse(qty) ?? 0;
    return n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);
  }
}

class PrintResult {
  final bool success;
  final String? error;

  const PrintResult({required this.success, this.error});
}
