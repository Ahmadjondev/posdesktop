import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_config.dart';

/// Persists app settings (POS URL, printer configuration) using SharedPreferences.
class SettingsService {
  static const _keyPosUrl = 'pos_url';
  static const _keyPrinterConfig = 'printer_config';
  static const _keyAutoStart = 'auto_start';
  static const _keySetupComplete = 'setup_complete';
  static const _defaultUrl = 'https://demo.digitex.uz/';

  late final SharedPreferences _prefs;

  SettingsService._();

  static Future<SettingsService> create() async {
    final service = SettingsService._();
    service._prefs = await SharedPreferences.getInstance();
    return service;
  }

  // ── POS URL ───────────────────────────────────────────────────────────

  String get posUrl => _prefs.getString(_keyPosUrl) ?? _defaultUrl;

  Future<void> setPosUrl(String url) async {
    await _prefs.setString(_keyPosUrl, url);
  }

  // ── Printer config ────────────────────────────────────────────────────

  PrinterConfig get printerConfig {
    final raw = _prefs.getString(_keyPrinterConfig);
    if (raw == null) return const PrinterConfig();
    try {
      return PrinterConfig.fromJson(
        json.decode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const PrinterConfig();
    }
  }

  Future<void> setPrinterConfig(PrinterConfig config) async {
    await _prefs.setString(_keyPrinterConfig, json.encode(config.toJson()));
  }

  // ── Auto-start ────────────────────────────────────────────────────────

  bool get autoStart => _prefs.getBool(_keyAutoStart) ?? false;

  Future<void> setAutoStart(bool value) async {
    await _prefs.setBool(_keyAutoStart, value);
  }

  // ── Setup completion ──────────────────────────────────────────────────

  bool get isSetupComplete => _prefs.getBool(_keySetupComplete) ?? false;

  Future<void> setSetupComplete(bool value) async {
    await _prefs.setBool(_keySetupComplete, value);
  }
}
