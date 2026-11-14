import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Checkout while signed out: "Sign in to place your order" over the
/// cart. True for "Sign in with email"; false for "Not now", the close
/// button, a tap outside or system back (the shopper stays on the cart).
Future<bool> showSignInSheet(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const SignInSheet(),
    ) ??
    false;

class SignInSheet extends StatelessWidget {
  const SignInSheet({super.key});

  static const String title = 'Sign in to place your order';
  static const String message =
      'Orders need a Fresh Market account. Sign in with your email and a '
      '6-digit code, then checkout opens straight away. Your cart stays as '
      'it is.';
  static const String ordersLine = 'See your orders any time in Account';
  static const String signInLabel = 'Sign in with email';
  static const String notNowLabel = 'Not now';
  static const String closeTooltip = 'Close';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDims.gutter,
          0,
          AppDims.gutter,
          AppDims.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: const Text(title, style: AppText.heading),
                  ),
                ),
                const SizedBox(width: 8),
                // The close button's icon on the gutter's edge.
                Transform.translate(
                  offset: Offset(
                    Directionality.of(context) == TextDirection.rtl ? -10 : 10,
                    0,
                  ),
                  child: IconButton(
                    key: const ValueKey('sign-in-sheet-close'),
                    icon: const Icon(Icons.close),
                    tooltip: closeTooltip,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppText.body.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ordersLine,
                    style: AppText.bodySmall.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Ink: signing in is not buying.
            FilledButton(
              key: const ValueKey('sign-in-sheet-sign-in'),
              style: AppButtons.dark,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(signInLabel, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 4),
            TextButton(
              key: const ValueKey('sign-in-sheet-not-now'),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(AppDims.controlTarget),
              ),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(notNowLabel, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
