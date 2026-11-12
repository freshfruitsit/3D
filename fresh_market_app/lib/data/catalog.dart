/// A "Shop By Category" tile.
class CategoryEntry {
  const CategoryEntry(this.label, this.asset, this.handle);

  /// Shown uppercase on the tile; used as the list title as written here.
  final String label;

  /// Bundled transparent cut-out photo.
  final String asset;

  /// Collection handle the tile opens.
  final String handle;
}

/// A horizontal product rail on Home.
class HomeRail {
  const HomeRail(this.title, this.handle);

  final String title;
  final String handle;
}

/// A banner of the Home carousel.
class HomeBanner {
  const HomeBanner(this.asset, this.handle, this.title);

  final String asset;

  /// Collection the banner opens.
  final String handle;

  /// Title of the list the banner opens.
  final String title;
}

/// A "Brands We Love" entry. The store's "brands" collection is empty, so a
/// brand opens Search pre-filled with [searchTerm].
class BrandEntry {
  const BrandEntry(this.name, this.asset, this.searchTerm);

  final String name;
  final String asset;
  final String searchTerm;
}

abstract final class Catalog {
  static const String logoAsset = 'assets/images/logo.png';
  static const String localAsset = 'assets/images/local.jpg';

  /// The 12 category tiles, in grid order.
  static const List<CategoryEntry> categories = [
    CategoryEntry('Fruits', 'assets/categories/fruits.png', 'fruits'),
    CategoryEntry(
        'Vegetables', 'assets/categories/vegetables.png', 'vegetables'),
    CategoryEntry('Meat', 'assets/categories/meat.png', 'fresh-meat'),
    CategoryEntry('Berries', 'assets/categories/berries.png', 'berries'),
    CategoryEntry(
        'Flowers', 'assets/categories/flowers.png', 'ambrosia-flowers'),
    CategoryEntry('Hampers', 'assets/categories/hampers.png', 'hampers'),
    CategoryEntry('Citrus', 'assets/categories/citrus.png', 'citrus'),
    CategoryEntry('Mangoes', 'assets/categories/mangoes.png', 'mangoes'),
    CategoryEntry(
        'Melons', 'assets/categories/melons.png', 'melons-pineapples'),
    CategoryEntry(
        'Tropical', 'assets/categories/tropical.png', 'tropical-exotic'),
    CategoryEntry('Greens', 'assets/categories/greens.png', 'lettuce-greens'),
    CategoryEntry('Herbs', 'assets/categories/herbs.png', 'fresh-herbs'),
  ];

  /// Home carousel banners, in order.
  static const List<HomeBanner> banners = [
    HomeBanner('assets/banners/banner_0.jpg', 'fruits', 'Fruits'),
    HomeBanner('assets/banners/banner_1.jpg', 'vegetables', 'Vegetables'),
    HomeBanner('assets/banners/banner_2.jpg', 'bulk-buy', 'Bulk Buy'),
  ];

  static const HomeRail topDeals = HomeRail("Today's Top Deals", 'fresh-meat');
  static const HomeRail bestDeals = HomeRail('Best Deals', 'best-deals');
  static const HomeRail freshPick =
      HomeRail('Fresh Pick For You', 'best-sellers');
  static const HomeRail berries = HomeRail('Berries', 'berries');
  static const HomeRail blooms =
      HomeRail('Seasonal Blooms', 'ambrosia-flowers');

  /// Rails shown above the "Brands We Love" row.
  static const List<HomeRail> railsBeforeBrands = [topDeals, bestDeals];

  /// Rails shown below the "Brands We Love" row.
  static const List<HomeRail> railsAfterBrands = [freshPick, berries, blooms];

  /// All five Home rails in display order.
  static const List<HomeRail> rails = [
    ...railsBeforeBrands,
    ...railsAfterBrands,
  ];

  /// "Brands We Love", in display order. Images come from the store's
  /// website.
  static const List<BrandEntry> brands = [
    BrandEntry('Chiquita Bananas', 'assets/brands/brand_0.png', 'Chiquita'),
    BrandEntry('Zespri Kiwi', 'assets/brands/brand_1.jpg', 'Zespri'),
    BrandEntry('Sebastiano Banana', 'assets/brands/brand_2.jpg', 'Sebastiano'),
    BrandEntry('Jazz Apple', 'assets/brands/brand_3.jpg', 'Jazz'),
    BrandEntry('Gems Mandarin', 'assets/brands/brand_4.jpg', 'Gems'),
    BrandEntry('Fruitway Pears', 'assets/brands/brand_5.jpg', 'Fruitway'),
    BrandEntry('Dazzle Apple', 'assets/brands/brand_6.jpg', 'Dazzle'),
    BrandEntry('Thai Fresh', 'assets/brands/brand_7.png', 'Thai'),
    BrandEntry('Pink Lady Apple', 'assets/brands/brand_8.png', 'Pink Lady'),
    BrandEntry('Juliet Apple', 'assets/brands/brand_9.jpg', 'Juliet'),
  ];

  /// The Deals tab.
  static const String dealsHandle = 'best-deals';
  static const String dealsTitle = 'Deals';

  /// The "Discover our fresh local products" card on Home.
  static const String localHandle = 'local-uae';
  static const String localTitle = 'Local UAE';

  /// Popular searches shown while the search field is empty.
  static const List<String> popularSearches = [
    'Strawberry',
    'Avocado',
    'Lamb',
    'Bouquet',
  ];
}
