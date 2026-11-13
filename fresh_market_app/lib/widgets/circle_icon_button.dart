import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'floating_nav_bar.dart';

/// A 44px round white button with a hairline and a soft shadow: back
/// arrows, the favourite heart and the cart button on product detail.
/// [badgeCount] above 0 adds the green count badge.
///
/// Screen readers hear a button named [semanticLabel] (or [tooltip]), with
/// its on/off state when [toggled] is set; the badge's digits are not read
/// on their own (put the count in [semanticLabel]).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.iconColor = AppColors.ink,
    this.badgeCount = 0,
    this.semanticLabel,
    this.toggled,
  });

  /// The standard back button; pops the nearest navigator.
  factory CircleIconButton.back(BuildContext context, {Key? key}) =>
      CircleIconButton(
        key: key,
        icon: Icons.arrow_back,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      );

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color iconColor;
  final int badgeCount;

  /// What screen readers hear; [tooltip] when null.
  final String? semanticLabel;

  /// The on/off state of a toggle (the favourite heart); null for a plain
  /// button.
  final bool? toggled;

  static const double size = AppDims.touch;

  @override
  Widget build(BuildContext context) {
    final button = DecoratedBox(
      decoration: const ShapeDecoration(
        shape: CircleBorder(),
        shadows: AppShadows.raised,
      ),
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(side: BorderSide(color: AppColors.hairline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      toggled: toggled,
      label: semanticLabel ?? tooltip,
      onTap: onPressed,
      // The tooltip (long press) and the badge's digits are not read
      // separately.
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: badgeCount > 0
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  button,
                  Positioned(
                    top: -3,
                    right: -3,
                    child: CountBadge(count: badgeCount),
                  ),
                ],
              )
            : button,
      ),
    );
  }
}
