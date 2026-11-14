import '../models/product.dart';

/// The store's marked-down products: the Deals tab, Home's "Best Deals"
/// rail and the "Deals of the day" offer.
///
/// The store's own "best-deals" collection has no product with a
/// compare-at price, so it would show no saving at all. These lists come
/// from Shopify's built-in "all" collection instead and keep only the
/// products whose shown variant really costs less than its compare-at
/// price: no card ever shows a saving the store does not have.
abstract final class Deals {
  /// Shopify's built-in collection that holds every product of the store.
  static const String sourceHandle = 'all';

  /// True when the variant a card shows (the first one in stock) is
  /// marked down.
  static bool isDeal(Product product) =>
      product.defaultVariant?.onSale ?? false;

  /// The deals among [products], biggest saving first: in stock before
  /// sold out, then by percentage off; equal ones keep the store's order.
  static List<Product> ranked(Iterable<Product> products) {
    final deals = [
      for (final (index, product) in products.where(isDeal).indexed)
        (index, product),
    ]..sort((a, b) {
        final byStock =
            (b.$2.available ? 1 : 0).compareTo(a.$2.available ? 1 : 0);
        if (byStock != 0) return byStock;
        final byPercent = _percent(b.$2).compareTo(_percent(a.$2));
        return byPercent != 0 ? byPercent : a.$1.compareTo(b.$1);
      });
    return [for (final entry in deals) entry.$2];
  }

  static int _percent(Product product) =>
      product.defaultVariant?.salePercent ?? 0;
}
