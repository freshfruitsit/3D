import 'package:material_ui/material_ui.dart';

import '../screens/assistant_screen.dart';
import '../theme/app_theme.dart';

/// The ink "Ask" pill (lime sparkle, white label) that opens the demo assistant, full screen (it
/// covers the bottom bar, like product detail).
///
/// It hugs its content: 48px high, about 104px wide. The shell places it
/// at the bottom right, above the floating bottom bar.
class AskButton extends StatelessWidget {
  const AskButton({super.key});

  static const double height = 48;

  /// Gap to leave between this button and the bottom bar below it.
  static const double gapAboveNavBar = 12;

  /// Opens the assistant over everything, bottom bar included.
  static Future<void> open(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => const AssistantScreen()),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Ask the Fresh Market assistant',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(height / 2)),
          boxShadow: [
            BoxShadow(
              color: Color(0x40111111),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: AppColors.ink,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => open(context),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 20,
                      color: AppColors.lime,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ask',
                      style: AppText.button.copyWith(color: Colors.white),
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
