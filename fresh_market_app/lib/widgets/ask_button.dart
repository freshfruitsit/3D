import 'package:material_ui/material_ui.dart';

import '../screens/assistant_screen.dart';
import '../theme/app_theme.dart';

/// The white "Ask" pill (green sparkle, ink label, soft shadow) that
/// opens the demo assistant full screen (it covers the bottom bar, like
/// product detail). White so it stands apart from the ink bottom bar.
///
/// It hugs its content: 48px high, about 96px wide. The shell places it
/// at the bottom right, above the floating bottom bar.
class AskButton extends StatelessWidget {
  const AskButton({super.key});

  static const double height = 48;

  /// Gap to leave between this button and the bottom bar below it.
  static const double gapAboveNavBar = 12;

  /// Opens the assistant over everything, bottom bar included.
  static Future<void> open(BuildContext context) => Navigator.of(
    context,
    rootNavigator: true,
  ).push(MaterialPageRoute<void>(builder: (_) => const AssistantScreen()));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask the Fresh Market assistant',
      onTap: () => open(context),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const ShapeDecoration(
          shape: StadiumBorder(),
          shadows: AppShadows.float,
        ),
        child: Material(
          color: AppColors.surface,
          shape: const StadiumBorder(
            side: BorderSide(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => open(context),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.only(left: 14, right: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 20,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ask',
                      // The pill keeps its 48px height at any text size.
                      textScaler: MediaQuery.textScalerOf(context)
                          .clamp(maxScaleFactor: 1.3),
                      style: AppText.button.copyWith(color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
