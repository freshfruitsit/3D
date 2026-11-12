import '../models/collection.dart';
import '../models/product.dart';
import 'shopify_api.dart';

/// In-memory [ShopifyApi] for tests. No network.
///
/// ```dart
/// final api = FakeShopifyApi.sample();          // a little of everything
/// final api = FakeShopifyApi(collections: {'fruits': [product]});
/// api.error = const NetworkException('offline'); // every call now fails
/// api.delay = const Duration(seconds: 1);        // to see loading states
/// ```
class FakeShopifyApi implements ShopifyApi {
  FakeShopifyApi({
    Map<String, List<Product>>? collections,
    this.error,
    this.delay = Duration.zero,
  }) : collectionsByHandle = collections ?? {};

  /// Sample data: every handle in [handles] gets the same six products
  /// (see [sampleProducts]).
  factory FakeShopifyApi.sample({
    Iterable<String> handles = const [
      'fresh-meat',
      'best-deals',
      'best-sellers',
      'berries',
      'ambrosia-flowers',
      'fruits',
      'vegetables',
      'local-uae',
    ],
  }) =>
      FakeShopifyApi(
        collections: {for (final h in handles) h: sampleProducts()},
      );

  /// Products by collection handle. A handle that is missing answers 404.
  final Map<String, List<Product>> collectionsByHandle;

  /// When set, every call throws it.
  ApiException? error;

  /// Artificial latency of every call.
  Duration delay;

  /// Every call made, e.g. `collectionProducts(fruits, page 1)`,
  /// `search(kiwi)`, `product(kiwi)`, `collections()`.
  final List<String> calls = [];

  Iterable<Product> get _allProducts sync* {
    final seen = <int>{};
    for (final list in collectionsByHandle.values) {
      for (final p in list) {
        if (seen.add(p.id)) yield p;
      }
    }
  }

  Future<void> _before(String call) async {
    calls.add(call);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final e = error;
    if (e != null) throw e;
  }

  @override
  Future<List<Product>> collectionProducts(
    String handle, {
    int page = 1,
    int limit = ShopifyApi.pageSize,
  }) async {
    await _before('collectionProducts($handle, page $page)');
    final all = collectionsByHandle[handle];
    if (all == null) {
      throw HttpStatusException(404, 'No collection "$handle"');
    }
    final start = (page - 1) * limit;
    if (start >= all.length) return const [];
    final end = start + limit > all.length ? all.length : start + limit;
    return all.sublist(start, end);
  }

  @override
  Future<List<Collection>> collections() async {
    await _before('collections()');
    var id = 1;
    return [
      for (final entry in collectionsByHandle.entries)
        Collection(
          id: id++,
          title: entry.key,
          handle: entry.key,
          productsCount: entry.value.length,
        ),
    ];
  }

  @override
  Future<List<Product>> search(String query, {int limit = 10}) async {
    await _before('search($query)');
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const [];
    return _allProducts
        .where((p) =>
            p.title.toLowerCase().contains(term) ||
            p.vendor.toLowerCase().contains(term))
        .take(limit)
        .toList();
  }

  @override
  Future<Product> product(String handle) async {
    await _before('product($handle)');
    for (final p in _allProducts) {
      if (p.handle == handle) return p;
    }
    throw HttpStatusException(404, 'No product "$handle"');
  }
}

/// Six products covering the cases screens must handle: two weights, a
/// sale, a local product, a sold-out product, a bouquet without tags and a
/// product with one sold-out weight. Values mirror real store data.
List<Product> sampleProducts() => const [
      Product(
        id: 1001,
        title: 'Zespri Kiwi Sungold',
        handle: 'zespri-kiwi-sungold',
        descriptionHtml: '<p>Golden, juicy and sweet.</p>'
            '<ul><li>Wash before cutting</li></ul>',
        vendor: 'Zespri',
        productType: 'Fruits',
        tags: ['1hr-delivery', 'AIR', 'By air', 'origin:New Zealand'],
        variants: [
          Variant(id: 2001, title: '500 GM', priceCents: 1995),
          Variant(id: 2002, title: '1 KG', priceCents: 3975),
        ],
        images: ['https://cdn.shopify.com/s/files/sample/kiwi.jpg?v=1'],
        options: [
          ProductOption(name: 'Weight', values: ['500 GM', '1 KG']),
        ],
      ),
      Product(
        id: 1002,
        title: 'Australian Beef Cubes',
        handle: 'australian-beef-cubes',
        descriptionHtml: '<p>Tender beef cubes.</p>',
        vendor: 'Rokn Al Lhom',
        productType: 'Meat',
        tags: ['origin:Australia'],
        variants: [
          Variant(
            id: 2003,
            title: 'Default Title',
            priceCents: 6250,
            compareAtCents: 11500,
          ),
        ],
        images: ['https://cdn.shopify.com/s/files/sample/beef.jpg?v=1'],
        options: [
          ProductOption(name: 'Title', values: ['Default Title']),
        ],
      ),
      Product(
        id: 1003,
        title: 'Cucumber',
        handle: 'cucumber',
        descriptionHtml: '<p>Crisp local cucumbers.</p>',
        vendor: 'Fresh Market',
        productType: 'Vegetables',
        tags: ['1hr-delivery', 'Local', 'UAE', 'origin:UAE'],
        variants: [
          Variant(id: 2004, title: '500 GM', priceCents: 250),
          Variant(id: 2005, title: '1 KG', priceCents: 475),
        ],
        images: ['https://cdn.shopify.com/s/files/sample/cucumber.jpg?v=1'],
        options: [
          ProductOption(name: 'Weight', values: ['500 GM', '1 KG']),
        ],
      ),
      Product(
        id: 1004,
        title: 'Blueberry',
        handle: 'blueberry',
        vendor: 'Fresh Market',
        productType: 'Fruits',
        tags: ['origin:Peru'],
        variants: [
          Variant(
            id: 2006,
            title: 'Default Title',
            priceCents: 3125,
            available: false,
          ),
        ],
        images: ['https://cdn.shopify.com/s/files/sample/blueberry.jpg?v=1'],
      ),
      Product(
        id: 1005,
        title: 'Pink Passion Flower Bouquet',
        handle: 'pink-passion-flower-bouquet',
        descriptionHtml: '<p>A hand-tied bouquet.</p>',
        vendor: 'Ambrosia',
        productType: 'Flowers',
        variants: [
          Variant(id: 2007, title: 'Default Title', priceCents: 30000),
        ],
        images: ['https://cdn.shopify.com/s/files/sample/bouquet.jpg?v=1'],
      ),
      Product(
        id: 1006,
        title: 'Strawberry',
        handle: 'strawberry',
        vendor: "Driscoll's",
        productType: 'Fruits',
        tags: ['1hr-delivery', 'AIR', 'origin:South Africa'],
        variants: [
          Variant(
            id: 2008,
            title: '250 GM',
            priceCents: 2050,
            available: false,
          ),
          Variant(
            id: 2009,
            title: '1 KG',
            priceCents: 7500,
            compareAtCents: 8295,
          ),
        ],
        images: ['https://cdn.shopify.com/s/files/sample/strawberry.jpg?v=1'],
        options: [
          ProductOption(name: 'Weight', values: ['250 GM', '1 KG']),
        ],
      ),
    ];
