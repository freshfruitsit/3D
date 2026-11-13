import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';
import 'intro_screen.dart';

/// The Account tab: a sign-in card (sign-in is not available in this
/// version), the way into the favourites list and a replay of the intro.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final favourites = context.select<FavouritesStore, int>((s) => s.count);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppDims.gutter,
            16,
            AppDims.gutter,
            AppDims.floatingSpace(context),
          ),
          children: [
            Semantics(
              header: true,
              child: const Text('Account', style: AppText.title),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: AppDecor.card,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: AppColors.subtle,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          size: 26,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sign in to see your orders and saved addresses',
                              style: AppText.cardHeading,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Sign-in is not available in this version.',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Signing in is not buying: ink, not the green CTA.
                  FilledButton(
                    style: AppButtons.dark,
                    onPressed: null,
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // One white card, rows split by hairlines.
            Container(
              decoration: AppDecor.card,
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    _AccountRow(
                      // Ink either way: filled when something is saved.
                      icon: favourites > 0
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: 'Favourites',
                      onTap: () => AppNav.openFavourites(context),
                      trailing: Text(
                        '$favourites',
                        semanticsLabel: favourites == 1
                            ? '1 saved product'
                            : '$favourites saved products',
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 52),
                    _AccountRow(
                      icon: Icons.play_circle_outline,
                      label: 'Watch the intro again',
                      onTap: () => _watchIntro(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Plays the intro over the whole screen (no bottom bar) and comes back
  /// here when it finishes.
  static Future<void> _watchIntro(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (routeContext) => IntroScreen(
            onDone: () => Navigator.of(routeContext).pop(),
          ),
        ),
      );
}

/// One tappable row of the account list: ink icon, label, optional value,
/// chevron.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: 4),
              ],
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: AppColors.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
