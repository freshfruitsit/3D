import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'models/product.dart';
import 'screens/checkout_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/search_screen.dart';
import 'state/cart_store.dart';

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

  /// Checkout for the current cart, full screen. Does nothing when the
  /// cart is empty.
  static Future<void> openCheckout(BuildContext context) async {
    final url = context.read<CartStore>().checkoutUrl;
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
