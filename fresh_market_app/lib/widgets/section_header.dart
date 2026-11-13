import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// A section heading drawn as an ink tag (white title and icon) that runs
/// in from the left edge of the screen and ends in a slant, followed by a
/// thin green slanted stripe, the only colour in it. An optional ink
/// "See all" link with a chevron sits on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onViewAll,
    this.icon,
    this.padding = const EdgeInsets.only(right: 8),
  });

  final String title;

  /// Shows "See all" when set.
  final VoidCallback? onViewAll;

  /// Icon before the title, white on the tag.
  final IconData? icon;

  /// Around the whole row. The tag itself always starts at the left edge
  /// of the row, so leave the left padding at 0 to reach the screen edge.
  final EdgeInsetsGeometry padding;

  /// The link's text.
  static const String seeAll = 'See all';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDims.touch),
        child: Row(
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: SectionTag(title: title, icon: icon),
              ),
            ),
            if (onViewAll != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  textStyle: AppText.link,
                  padding: const EdgeInsets.only(left: 8, right: 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(seeAll, semanticsLabel: '$seeAll $title'),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The ink, slanted heading tag with its green stripe, on its own (the
/// Categories tab title uses it).
class SectionTag extends StatelessWidget {
  const SectionTag({super.key, required this.title, this.icon});

  final String title;
  final IconData? icon;

  /// Horizontal size of the slant at the tag's right end.
  static const double slant = 14;

  /// Width of the accent stripe after the tag, including its gap.
  static const double accentSpace = 13;

  static const double height = 38;

  /// Vertical padding around the title inside the tag.
  static const double verticalPadding = 7;

  /// The style of the title.
  static final TextStyle titleStyle = AppText.heading.copyWith(
    color: AppColors.onDark,
    letterSpacing: 0,
    height: 1.2,
  );

  /// The height of a one-line tag at the current text size.
  static double heightOf(BuildContext context) {
    final text = MediaQuery.textScalerOf(context).scale(titleStyle.fontSize!) *
        titleStyle.height!;
    final h = text + 2 * verticalPadding;
    return h < height ? height : h;
  }

  /// The tag's fill and the stripe's colour.
  static const Color fill = AppColors.ink;
  static const Color accent = AppColors.green;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: CustomPaint(
        painter: const _TagPainter(fill: fill, accent: accent),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDims.gutter,
              verticalPadding,
              slant + accentSpace + 12,
              verticalPadding,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: AppColors.onDark),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  // Two lines (a taller tag) at a large font size rather
                  // than "Today's Top…".
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagPainter extends CustomPainter {
  const _TagPainter({required this.fill, required this.accent});

  final Color fill;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const slant = SectionTag.slant;
    final h = size.height;
    final tagRight = size.width - SectionTag.accentSpace;
    final tag = Path()
      ..moveTo(0, 0)
      ..lineTo(tagRight, 0)
      ..lineTo(tagRight - slant, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(tag, Paint()..color = fill);

    // A thin stripe parallel to the slant, 4px after it.
    const gap = 4.0;
    const width = 6.0;
    final stripe = Path()
      ..moveTo(tagRight + gap, 0)
      ..lineTo(tagRight + gap + width, 0)
      ..lineTo(tagRight + gap + width - slant, h)
      ..lineTo(tagRight + gap - slant, h)
      ..close();
    canvas.drawPath(stripe, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_TagPainter old) =>
      old.fill != fill || old.accent != accent;
}
