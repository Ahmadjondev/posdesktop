import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import '../models/receipt_data.dart';
import '../services/printer_service.dart';
import '../services/settings_service.dart';
import 'settings_screen.dart';

/// Main screen: full-window WebView loading the POS web app.
/// Listens for postMessage from the web app to trigger silent printing.
/// Has a persistent navigation toolbar at the top.
class HomeScreen extends StatefulWidget {
  final SettingsService settings;

  const HomeScreen({super.key, required this.settings});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final _log = Logger('HomeScreen');

class _HomeScreenState extends State<HomeScreen> {
  // Platform-specific WebView controllers
  ww.WebviewController? _winController;
  wf.WebViewController? _macController;

  final _printer = PrinterService();
  bool _isReady = false;
  bool _isPageLoading = true;
  bool _isPrinting = false;
  String? _error;

  // Navigation state
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  // ── WebView Init ──────────────────────────────────────────────────────

  Future<void> _initWebView() async {
    try {
      if (Platform.isWindows) {
        await _initWindows();
      } else {
        _initMacOS();
      }
    } catch (e) {
      _log.severe('WebView initialization failed: $e');
      if (mounted) {
        setState(() => _error = 'WebView yuklashda xatolik: $e');
      }
    }
  }

  Future<void> _initWindows() async {
    final controller = ww.WebviewController();
    await controller.initialize();
    controller.webMessage.listen(_onWebMessage);

    // Track navigation history for back/forward buttons
    controller.historyChanged.listen((event) {
      if (mounted) {
        setState(() {
          _canGoBack = event.canGoBack;
          _canGoForward = event.canGoForward;
        });
      }
    });

    // Track loading state
    controller.loadingState.listen((state) {
      if (mounted) {
        setState(() {
          _isPageLoading = state == ww.LoadingState.loading;
        });
      }
    });

    final url = widget.settings.posUrl;
    _log.info('Loading POS URL: $url');
    await controller.loadUrl(url);

    _winController = controller;
    if (mounted) setState(() => _isReady = true);
  }

  void _initMacOS() {
    final url = widget.settings.posUrl;
    _log.info('Loading POS URL (macOS): $url');

    final controller = wf.WebViewController()
      ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        wf.NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _isPageLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isPageLoading = false);
            _injectBridgeShim();
            _updateMacNavState();
          },
          onWebResourceError: (err) {
            _log.warning('WebView error: ${err.description}');
            if (err.isForMainFrame == true && mounted) {
              setState(() {
                _isPageLoading = false;
                _error = err.description;
              });
            }
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (msg) {
          _onWebMessage(msg.message);
        },
      )
      ..loadRequest(Uri.parse(url));

    _macController = controller;
    setState(() => _isReady = true);
  }

  /// Query macOS WebView for navigation state (no stream like Windows).
  Future<void> _updateMacNavState() async {
    if (_macController == null) return;
    final back = await _macController!.canGoBack();
    final forward = await _macController!.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  /// Inject a shim so the Vue desktop-bridge.js works on macOS too.
  void _injectBridgeShim() {
    _macController?.runJavaScript('''
      (function() {
        if (!window.chrome) window.chrome = {};
        if (!window.chrome.webview) {
          var listeners = [];
          window.chrome.webview = {
            postMessage: function(msg) {
              if (window.FlutterBridge) {
                window.FlutterBridge.postMessage(typeof msg === 'string' ? msg : JSON.stringify(msg));
              }
            },
            addEventListener: function(type, handler) { listeners.push(handler); },
            removeEventListener: function(type, handler) {
              listeners = listeners.filter(function(h) { return h !== handler; });
            },
            _dispatch: function(data) {
              var evt = { data: data };
              listeners.forEach(function(h) { try { h(evt); } catch(e) {} });
            }
          };
        }
      })();
    ''');
  }

  // ── Navigation Actions ────────────────────────────────────────────────

  void _goBack() {
    if (!_canGoBack) return;
    if (Platform.isWindows) {
      _winController?.goBack();
    } else {
      _macController?.goBack();
      Future.delayed(const Duration(milliseconds: 300), _updateMacNavState);
    }
  }

  void _goForward() {
    if (!_canGoForward) return;
    if (Platform.isWindows) {
      _winController?.goForward();
    } else {
      _macController?.goForward();
      Future.delayed(const Duration(milliseconds: 300), _updateMacNavState);
    }
  }

  void _reload() {
    if (!_isReady) return;
    setState(() {
      _error = null;
      _isPageLoading = true;
    });
    if (Platform.isWindows) {
      _winController?.reload();
    } else {
      _macController?.reload();
    }
  }

  // ── Message Handling ──────────────────────────────────────────────────

  void _onWebMessage(dynamic message) async {
    _log.info('Received web message: \$message');

    try {
      final Map<String, dynamic> parsed;
      if (message is String) {
        parsed = json.decode(message) as Map<String, dynamic>;
      } else if (message is Map) {
        parsed = Map<String, dynamic>.from(message);
      } else {
        _log.warning('Unknown message type: ${message.runtimeType}');
        return;
      }

      final type = parsed['type'] as String?;

      if (type == 'PRINT') {
        await _handlePrint(parsed['data'] as Map<String, dynamic>);
      } else if (type == 'PING') {
        _postMessage({'type': 'PONG', 'desktop': true});
      }
    } catch (e) {
      _log.severe('Error processing web message: $e');
      _postMessage({
        'type': 'PRINT_RESULT',
        'success': false,
        'error': 'Xabarni qayta ishlashda xatolik: $e',
      });
    }
  }

  Future<void> _handlePrint(Map<String, dynamic> data) async {
    if (_isPrinting) {
      _postMessage({
        'type': 'PRINT_RESULT',
        'success': false,
        'error': 'Chop etish jarayoni allaqachon ketmoqda',
      });
      return;
    }

    setState(() => _isPrinting = true);

    try {
      final receipt = ReceiptData.fromJson(data);
      final config = widget.settings.printerConfig;

      if (!config.isConfigured) {
        _log.warning('Printer not configured — aborting print');
        _postMessage({
          'type': 'PRINT_RESULT',
          'success': false,
          'error': 'Printer sozlanmagan. Sozlamalarda printerni tanlang.',
        });
        return;
      }

      _log.info(
        'Printing receipt ${receipt.saleNumber} via ${config.connectionLabel}',
      );

      final result = await _printer.printReceipt(receipt, config);

      _postMessage({
        'type': 'PRINT_RESULT',
        'success': result.success,
        if (!result.success) 'error': result.error,
      });

      if (result.success) {
        _log.info('Receipt ${receipt.saleNumber} printed successfully');
      } else {
        _log.warning('Print failed: ${result.error}');
      }
    } catch (e) {
      _log.severe('Print error: $e');
      _postMessage({
        'type': 'PRINT_RESULT',
        'success': false,
        'error': 'Chop etishda xatolik: $e',
      });
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _postMessage(Map<String, dynamic> msg) {
    try {
      final encoded = json.encode(msg);
      if (Platform.isWindows) {
        _winController?.postWebMessage(encoded);
      } else {
        _macController?.runJavaScript(
          'window.chrome.webview._dispatch($encoded);',
        );
      }
    } catch (e) {
      _log.severe('Failed to post message to WebView: $e');
    }
  }

  void _openSettings() async {
    final reload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
    if (reload == true && _isReady) {
      final url = widget.settings.posUrl;
      if (Platform.isWindows) {
        _winController?.loadUrl(url);
      } else {
        _macController?.loadRequest(Uri.parse(url));
      }
    }
  }

  @override
  void dispose() {
    _winController?.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.comma, control: true):
              _openSettings,
          const SingleActivator(LogicalKeyboardKey.f5): _reload,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
              _goBack,
          const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
              _goForward,
          if (Platform.isWindows)
            const SingleActivator(LogicalKeyboardKey.f12): () {
              if (_isReady) _winController?.openDevTools();
            },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            children: [
              // ── Persistent navigation toolbar ──
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    _NavButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Orqaga (Alt+\u2190)',
                      onPressed: _canGoBack ? _goBack : null,
                    ),
                    _NavButton(
                      icon: Icons.arrow_forward_rounded,
                      tooltip: 'Oldinga (Alt+\u2192)',
                      onPressed: _canGoForward ? _goForward : null,
                    ),
                    _NavButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Yangilash (F5)',
                      onPressed: _isReady ? _reload : null,
                    ),
                    const Spacer(),
                    // ── Printer status chip ──
                    _PrinterStatusChip(settings: widget.settings),
                    const SizedBox(width: 4),
                    _NavButton(
                      icon: Icons.settings_rounded,
                      tooltip: 'Sozlamalar (Ctrl+,)',
                      onPressed: _openSettings,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),

              // ── Page loading indicator ──
              if (_isReady && _isPageLoading)
                LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  color: Theme.of(context).colorScheme.primary,
                )
              else
                const SizedBox(height: 3),

              // ── WebView / Error / Loading ──
              Expanded(
                child: Stack(
                  children: [
                    if (_error != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                size: 64,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Sahifani yuklashda xatolik',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () {
                                  setState(() => _error = null);
                                  _initWebView();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Qayta urinish'),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: _openSettings,
                                icon: const Icon(Icons.settings),
                                label: const Text('Sozlamalarni tekshiring'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (!_isReady)
                      const Center(child: CircularProgressIndicator())
                    else if (Platform.isWindows && _winController != null)
                      ww.Webview(_winController!)
                    else if (_macController != null)
                      wf.WebViewWidget(controller: _macController!),

                    // ── Print indicator ──
                    if (_isPrinting)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(40),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Chop etilmoqda...'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small icon button for the navigation toolbar.
class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: onPressed != null
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withAlpha(80),
      ),
    );
  }
}

/// Compact chip in the toolbar showing the active printer target.
class _PrinterStatusChip extends StatelessWidget {
  final SettingsService settings;

  const _PrinterStatusChip({required this.settings});

  @override
  Widget build(BuildContext context) {
    final config = settings.printerConfig;
    final configured = config.isConfigured;
    final theme = Theme.of(context);

    return Tooltip(
      message: configured
          ? '${config.name} \u2014 ${config.connectionLabel}'
          : 'Printer sozlanmagan',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: configured
              ? theme.colorScheme.primaryContainer.withAlpha(120)
              : theme.colorScheme.errorContainer.withAlpha(120),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              configured ? Icons.print_rounded : Icons.print_disabled_rounded,
              size: 14,
              color: configured
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            const SizedBox(width: 4),
            Text(
              configured ? config.name : 'Printer yo\u02BBq',
              style: theme.textTheme.labelSmall?.copyWith(
                color: configured
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
