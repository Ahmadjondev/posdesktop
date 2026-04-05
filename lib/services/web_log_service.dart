import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

final _log = Logger('WebLogService');

/// Persists web app logs (console.error, console.warn, uncaught exceptions)
/// to a rolling text file in the app's documents directory.
///
/// Developers can copy the log file to their laptop for debugging.
/// File location: `<Documents>/digitex_pos_logs/web_log.txt`
class WebLogService {
  WebLogService._();
  static final instance = WebLogService._();

  File? _logFile;
  IOSink? _sink;

  /// Max file size before rotation (2 MB).
  static const _maxBytes = 2 * 1024 * 1024;

  /// Initializes the log directory and file. Safe to call multiple times.
  Future<void> init() async {
    if (_logFile != null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/digitex_pos_logs');
      if (!await dir.exists()) await dir.create(recursive: true);
      _logFile = File('${dir.path}/web_log.txt');
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _log.info('Web log file: ${_logFile!.path}');
    } catch (e) {
      _log.severe('Failed to init web log file: $e');
    }
  }

  /// Appends a log entry.
  void write(String level, String message, {String? url, String? timestamp}) {
    if (_sink == null) return;
    final ts = timestamp ?? DateTime.now().toIso8601String();
    final line = '[$ts] [$level] ${url != null ? '($url) ' : ''}$message\n';
    _sink!.write(line);

    // Rotate if file exceeds max size (check every write is cheap on SSD/HDD)
    _rotateIfNeeded();
  }

  Future<void> _rotateIfNeeded() async {
    try {
      final file = _logFile;
      if (file == null || !await file.exists()) return;
      final size = await file.length();
      if (size < _maxBytes) return;

      // Close current sink, rename to .old.txt, re-open
      await _sink?.flush();
      await _sink?.close();
      final oldFile = File('${file.parent.path}/web_log.old.txt');
      if (await oldFile.exists()) await oldFile.delete();
      await file.rename(oldFile.path);
      _logFile = File('${file.parent.path}/web_log.txt');
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _log.info('Rotated web log file');
    } catch (e) {
      _log.warning('Log rotation failed: $e');
    }
  }

  /// Returns the path to the log directory (for "Open in Explorer/Finder").
  Future<String> get logDirectoryPath async {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/digitex_pos_logs';
  }

  /// Returns the full path to the current log file.
  String? get logFilePath => _logFile?.path;

  /// Flushes buffered writes to disk.
  Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// Disposes the file sink.
  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _logFile = null;
  }
}
