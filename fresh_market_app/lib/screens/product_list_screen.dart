import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// STUB: replaced by the screen's owner. Keep the class name and
/// constructor(s): the shell and AppNav depend on them.
class ProductListScreen extends StatelessWidget {
  /// Products of one collection, loaded page by page.
  const ProductListScreen.collection({
    super.key,
    required String this.handle,
    required this.title,
  });

  /// The shopper's favourites, from the FavouritesStore (no network).
  const ProductListScreen.favourites({super.key})
      : handle = null,
        title = 'Favourites';

  /// Collection handle; null for the favourites list.
  final String? handle;
  final String title;

  bool get isFavourites => handle == null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(child: Text(title, style: AppText.heading)),
      ),
    );
  }
}
