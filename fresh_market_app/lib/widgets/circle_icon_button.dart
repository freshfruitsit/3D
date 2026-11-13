import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';
import 'floating_nav_bar.dart';

/// A 44px white round button with a border: back arrows, the favourite
/// heart and the cart button on product detail. [badgeCount] above 0 adds
/// the lime count badge.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.iconColor = AppColors.ink,
    this.badgeCount = 0,
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

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: AppDims.touch,
          height: AppDims.touch,
          child: Icon(icon, size: 22, color: iconColor),
        ),
      ),
    );
    return Tooltip(
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
    );
  }
}
