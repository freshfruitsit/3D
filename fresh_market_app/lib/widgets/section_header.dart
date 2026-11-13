import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The colour of a section's heading tag. All three come from the logo's
/// UAE flag ribbon.
enum SectionTone {
  green(AppColors.brand, AppColors.red),
  red(AppColors.red, AppColors.brand),
  black(AppColors.ink, AppColors.brand);

  const SectionTone(this.fill, this.accent);

  /// The tag itself; its text is white.
  final Color fill;

  /// The thin slanted stripe after the tag, and nothing else.
  final Color accent;

  /// Colour of the "View all" link next to a tag of this tone.
  Color get link => this == SectionTone.black ? AppColors.ink : fill;
}

/// A section heading drawn as a coloured tag that runs in from the left
/// edge of the screen and ends in a slant, followed by a thin slanted
/// stripe in a second flag colour. An optional "View all" link sits on
/// the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onViewAll,
    this.tone = SectionTone.green,
    this.icon,
    this.padding = const EdgeInsets.only(right: 8),
  });

  final String title;
  final VoidCallback? onViewAll;
  final SectionTone tone;

  /// White icon before the title.
  final IconData? icon;

  /// Around the whole row. The tag itself always starts at the left edge
  /// of the row, so leave the left padding at 0 to reach the screen edge.
  final EdgeInsetsGeometry padding;

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
                child: SectionTag(title: title, tone: tone, icon: icon),
              ),
            ),
            if (onViewAll != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(foregroundColor: tone.link),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View all', semanticsLabel: 'View all $title'),
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

/// The coloured, slanted heading tag on its own.
class SectionTag extends StatelessWidget {
  const SectionTag({
    super.key,
    required this.title,
    this.tone = SectionTone.green,
    this.icon,
  });

  final String title;
  final SectionTone tone;
  final IconData? icon;

  /// Horizontal size of the slant at the tag's right end.
  static const double slant = 14;

  /// Width of the accent stripe after the tag, including its gap.
  static const double accentSpace = 13;

  static const double height = 38;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: title,
      excludeSemantics: true,
      child: CustomPaint(
        painter: _TagPainter(fill: tone.fill, accent: tone.accent),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDims.gutter,
              7,
              slant + accentSpace + 12,
              7,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: Colors.white),
                  const SizedBox(width: 7),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardHeading.copyWith(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      height: 1.2,
                    ),
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
    const width = 7.0;
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
