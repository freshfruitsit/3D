import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'models/product.dart';
import 'screens/checkout_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/search_screen.dart';
import 'services/shopify_api.dart';
import 'state/cart_store.dart';
import 'theme/app_theme.dart';

/// Every way of moving between screens. Screens call these instead of
/// building routes themselves, so the bottom bar rules stay in one place:
/// lists and search open inside the current tab (bar visible, tab stays
/// highlighted); product detail and checkout cover the whole screen.
abstract final class AppNav {
  /// A collection's product list (category tile, banner, "View all",
  /// "Discover now").
  static Future<void> openCollection(
    BuildContext context, {
    required String handle,
    required String title,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductListScreen.collection(handle: handle, title: title),
        ),
      );

  /// The favourites list (Account).
  static Future<void> openFavourites(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProductListScreen.favourites(),
        ),
      );

  /// Search, optionally pre-filled (brands, popular chips).
  static Future<void> openSearch(BuildContext context, {String? initialQuery}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SearchScreen(initialQuery: initialQuery),
        ),
      );

  /// Product detail, full screen (no bottom bar).
  static Future<void> openProduct(BuildContext context, Product product) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );

  /// Shown when cart lines had to be removed because the store no longer
  /// has them.
  static const String removedItemsMessage =
      'Some items are no longer available and were removed.';

  /// Says [message] above the floating bottom bar and the Ask button, or
  /// [bottomMargin] above the bottom of a screen that has neither.
  static void showNotice(
    BuildContext context,
    String message, {
    double? bottomMargin,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            AppDims.gutter,
            0,
            AppDims.gutter,
            bottomMargin ?? AppDims.floatingSpace(context),
          ),
        ),
      );
  }

  /// Checkout for the current cart, full screen. Does nothing when the
  /// cart is empty.
  ///
  /// The cart is first checked against the store, because Shopify refuses
  /// a checkout that contains a variant it no longer has. If lines had to
  /// be removed the shopper stays on the cart and is told so.
  static Future<void> openCheckout(BuildContext context) async {
    final cart = context.read<CartStore>();
    if (cart.isEmpty) return;
    final removed = await cart
        .revalidate(context.read<ShopifyApi>())
        .timeout(const Duration(seconds: 8), onTimeout: () => 0);
    if (!context.mounted) return;
    if (removed > 0) {
      showNotice(context, removedItemsMessage);
      return;
    }
    final url = cart.checkoutUrl;
    if (url == null) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => CheckoutScreen(url: url)),
    );
  }

  /// Closes any full-screen page (product detail, checkout) and shows
  /// [tab]. Choosing the tab that is already showing returns it to its
  /// first screen. Use for "View cart" and "Start shopping".
  static void goToTab(BuildContext context, AppTab tab) {
    final shell = context.read<ShellController>();
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
    shell.select(tab);
  }
}
