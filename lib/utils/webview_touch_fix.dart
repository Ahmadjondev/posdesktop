import 'package:flutter/widgets.dart';

/// Workaround for webview_windows touch focus bug.
///
/// On Windows touchscreen devices, the Flutter parent HWND reclaims focus
/// immediately after a touch-up event, preventing WebView2's composition
/// layer from retaining focus. This causes input fields to not activate
/// and soft keyboard to dismiss instantly.
///
/// Focus handling and click-debounce logic is done entirely in the JS
/// layer via addScriptToExecuteOnDocumentCreated (see home_screen.dart).
/// This wrapper exists as a logical boundary for the fix and can be
/// extended with Dart-side logic if needed in the future.
///
/// See: https://github.com/jnschulze/flutter-webview-windows/issues/183
class WebviewTouchFix extends StatelessWidget {
  const WebviewTouchFix({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // All touch/click fix logic is handled by the injected JS shim.
    // Previous approach of re-dispatching synthetic pointer events
    // caused double-tap/double-click artifacts on buttons.
    return child;
  }
}
