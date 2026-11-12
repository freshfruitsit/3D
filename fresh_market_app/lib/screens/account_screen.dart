import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';

/// The Account tab: a sign-in card (sign-in is not available in this
/// version) and the way into the favourites list.
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
            AppDims.bottomBarSpace(context),
          ),
          children: [
            const Text('Account', style: AppText.title),
            const SizedBox(height: 16),
            Container(
              decoration: AppDecor.card,
              padding: const EdgeInsets.all(16),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  SizedBox(height: 14),
                  FilledButton(onPressed: null, child: Text('Sign in')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: AppDecor.card,
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => AppNav.openFavourites(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          favourites > 0
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 22,
                          color: favourites > 0 ? AppColors.red : AppColors.ink,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Favourites', style: AppText.cardHeading),
                        ),
                        Text(
                          '$favourites',
                          semanticsLabel: favourites == 1
                              ? '1 saved product'
                              : '$favourites saved products',
                          style: AppText.caption.copyWith(fontSize: 14),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 22,
                          color: AppColors.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
