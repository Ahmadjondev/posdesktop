import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_windows/webview_windows.dart' as ww;

/// Workaround for webview_windows touch focus bug.
///
/// On Windows touchscreen devices, the Flutter parent HWND reclaims focus
/// immediately after a touch-up event, preventing WebView2's composition
/// layer from retaining focus. This causes input fields to not activate
/// and keyboard input to never route to the WebView.
///
/// The root cause: `SendPointerInput(PT_TOUCH)` does NOT transfer Win32
/// focus to the WebView2 controller, unlike `SendMouseInput` which does.
/// JS `element.focus()` only sets DOM focus but without Win32 focus,
/// keyboard events never reach the WebView2 process.
///
/// Fix: On touch-up, call `ICoreWebView2Controller::MoveFocus()` via the
/// patched webview_windows plugin to transfer OS-level focus to WebView2.
///
/// See: https://github.com/jnschulze/flutter-webview-windows/issues/183
class WebviewTouchFix extends StatelessWidget {
  const WebviewTouchFix({
    super.key,
    required this.child,
    required this.controller,
  });

  final Widget child;
  final ww.WebviewController controller;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (event) {
        if (event.kind == PointerDeviceKind.touch) {
          // Transfer Win32 focus to the WebView2 controller.
          // Reason 0 = COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC
          controller.moveFocus(reason: 0);
        }
      },
      child: child,
    );
  }
}
