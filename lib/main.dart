import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart' as ww;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('[${record.level.name}] ${record.loggerName}: ${record.message}');
  });

  // Configure WebView2 persistent cache directory (Windows only).
  // Must be called before any WebviewController is created.
  if (Platform.isWindows) {
    final appSupport = await getApplicationSupportDirectory();
    final userDataPath = '${appSupport.path}/webview2_cache';
    await ww.WebviewController.initializeEnvironment(
      userDataPath: userDataPath,
    );
  }

  // Window configuration
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    minimumSize: Size(1024, 768),
    center: true,
    title: 'Digitex POS',
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  // Settings
  final settings = await SettingsService.create();

  runApp(DigitexPosApp(settings: settings));
}
