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

    // Optimize for low-end hardware (e.g. Intel Core i3-2100, 2-core, Intel HD 2000).
    // These flags reduce process count, disable GPU (avoids crashes on old iGPUs
    // that lack DX11/ANGLE support), and activate Chromium's low-end device mode.
    const lowEndFlags = [
      '--disable-gpu',
      '--disable-gpu-compositing',
      '--enable-low-end-device-mode',
      '--renderer-process-limit=1',
      '--process-per-site',
      '--disable-features=Vulkan,D3D12,VaapiVideoDecoder,Translate',
      '--disable-background-networking',
      '--disable-client-side-phishing-detection',
      '--disable-sync',
      '--disable-default-apps',
      '--js-flags=--max-old-space-size=256',
    ];

    await ww.WebviewController.initializeEnvironment(
      userDataPath: userDataPath,
      additionalArguments: lowEndFlags.join(' '),
    );
  }

  // Window configuration
  await windowManager.ensureInitialized();
  
  final windowOptions = WindowOptions(
    minimumSize: const Size(1024, 600),
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
