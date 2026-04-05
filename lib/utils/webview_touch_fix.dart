import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Workaround for webview_windows touch focus bug.
///
/// On Windows touchscreen devices, the Flutter parent HWND reclaims focus
/// immediately after a touch-up event, preventing WebView2's composition
/// layer from retaining focus. This causes input fields to not activate
/// and soft keyboard to dismiss instantly.
///
/// This widget wraps the WebView and re-dispatches a synthetic pointer
/// sequence on touch-up with a short delay, giving WebView2 enough time
/// to process focus before Flutter steals it back.
///
/// See: https://github.com/jnschulze/flutter-webview-windows/issues/183
class WebviewTouchFix extends StatelessWidget {
  const WebviewTouchFix({
    super.key,
    required this.child,
    this.touchDelay = const Duration(milliseconds: 100),
  });

  final Widget child;
  final Duration touchDelay;

  /// Track last tap position to avoid re-dispatching the same location,
  /// which would cause double-tap artifacts.
  static Offset _lastTapPosition = Offset.zero;

  void _onTapUp(TapUpDetails details) {
    // Only intercept touch events, not mouse
    if (details.kind != PointerDeviceKind.touch) return;

    final position = details.globalPosition;

    // Skip if same position (avoids re-entry loops)
    if (position == _lastTapPosition) return;
    _lastTapPosition = position;

    // Re-dispatch a synthetic pointer sequence after a delay.
    // This gives WebView2's composition controller time to acquire
    // and retain focus before Flutter's window proc reclaims it.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await Future.delayed(touchDelay);

        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(
            position: position,
            kind: PointerDeviceKind.touch,
            size: 70,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 36));

        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            position: position,
            kind: PointerDeviceKind.touch,
            size: 70,
          ),
        );
      } catch (_) {
        // Ignore — widget may have been disposed during the delay
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(onTapUp: _onTapUp, child: child);
  }
}
