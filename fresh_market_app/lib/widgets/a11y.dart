import 'package:flutter/semantics.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Says [message] to a screen reader (TalkBack, VoiceOver) without moving
/// its focus. Use it for changes the shopper caused that the screen does
/// not otherwise read out ("Added Kiwi. 1 in cart").
void announce(BuildContext context, String message) {
  final view = View.maybeOf(context);
  if (view == null || message.isEmpty) return;
  SemanticsService.sendAnnouncement(
    view,
    message,
    Directionality.maybeOf(context) ?? TextDirection.ltr,
  );
}

/// The largest font size, at most [style]'s, at which every word of
/// [label] fits [width] on its own line, so a long word is never broken in
/// the middle ("Vegetabl|es") at a large system font size.
double fittingFontSize(
  String label,
  TextStyle style,
  TextScaler scaler,
  double width,
) {
  double widestWord(double fontSize) {
    var widest = 0.0;
    for (final word in label.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(text: word, style: style.copyWith(fontSize: fontSize)),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }

  var fontSize = style.fontSize!;
  if (width <= 0) return fontSize;
  // A few rounds, as large-font scaling is not always linear.
  for (var round = 0; round < 4; round++) {
    final widest = widestWord(fontSize);
    if (widest <= width) break;
    fontSize = fontSize * width / widest * 0.98;
  }
  return fontSize;
}

/// [style] as a [Text] in [context] really draws it: merged over the
/// inherited text style, and bold when the system asks for bold text.
/// Measure with this, so a measurement and the drawn text agree.
TextStyle effectiveTextStyle(BuildContext context, TextStyle style) {
  var effective = DefaultTextStyle.of(context).style.merge(style);
  if (MediaQuery.boldTextOf(context)) {
    effective = effective.merge(const TextStyle(fontWeight: FontWeight.bold));
  }
  return effective;
}

/// Draws a visible focus ring around whatever has keyboard focus (hardware
/// keyboard, D-pad, Switch Access), on every screen: 2px ink inside 2px
/// white, so it reads on white (ink, 18.9:1), on the ink bar and on green
/// fills (white, 18.9:1 and 5.3:1). Nothing is drawn while the shopper
/// uses touch.
class FocusRingLayer extends StatefulWidget {
  const FocusRingLayer({super.key, required this.child});

  final Widget child;

  @override
  State<FocusRingLayer> createState() => FocusRingLayerState();
}

class FocusRingLayerState extends State<FocusRingLayer> {
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  /// The rectangle the ring is drawn around (global coordinates), or null
  /// when no ring shows.
  Rect? get ringRect => _ringRect();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_changed);
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_changed);
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    _repaint.dispose();
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode _) => _changed();

  void _changed() {
    if (!mounted) return;
    // After this frame's layout, so the focused control is where it will
    // be drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _repaint.value++;
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Rect? _ringRect() {
    if (FocusManager.instance.highlightMode !=
        FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node is FocusScopeNode || node.context == null) {
      return null;
    }
    // A text field shows its own ink border when focused.
    if (node.context!.findAncestorWidgetOfExactType<EditableText>() != null) {
      return null;
    }
    final box = node.context!.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final rect = node.rect;
    final screen = MediaQuery.sizeOf(context);
    // A focused page or list is not a control: no ring around the screen.
    if (rect.width * rect.height > screen.width * screen.height * 0.5) {
      return null;
    }
    return rect;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        if (FocusManager.instance.highlightMode ==
            FocusHighlightMode.traditional) {
          _repaint.value++;
        }
        return false;
      },
      child: Stack(
        textDirection: TextDirection.ltr,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FocusRingPainter(this, _repaint),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.layer, Listenable repaint) : super(repaint: repaint);

  final FocusRingLayerState layer;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = layer.ringRect;
    if (rect == null) return;
    final box = layer.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = rect.shift(-box.localToGlobal(Offset.zero));
    final inner = RRect.fromRectAndRadius(
      local.inflate(2),
      const Radius.circular(AppDims.controlRadius),
    );
    canvas
      ..drawRRect(
        inner.inflate(2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.onDark,
      )
      ..drawRRect(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.ink,
      );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) => true;
}
