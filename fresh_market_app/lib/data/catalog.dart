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

  /// Shown uppercase on the tile.
  final String name;
  final String asset;
  final String searchTerm;
}

/// A portrait banner of the "Offers" row on Home.
class PromoEntry {
  const PromoEntry(this.asset, this.handle, this.title);

  final String asset;

  /// Collection the banner opens.
  final String handle;

  /// Title of the list the banner opens; also its spoken label.
  final String title;
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

  /// Rails shown above the "Brands We Love" grid.
  static const List<HomeRail> railsBeforeBrands = [topDeals, bestDeals];

  /// Rails shown between the "Brands We Love" grid and the "Offers" row.
  static const List<HomeRail> railsAfterBrands = [freshPick];

  /// Rails shown below the "Offers" row.
  static const List<HomeRail> railsAfterOffers = [berries, blooms];

  /// All five Home rails in display order.
  static const List<HomeRail> rails = [
    ...railsBeforeBrands,
    ...railsAfterBrands,
    ...railsAfterOffers,
  ];

  /// "Brands We Love", in grid order. Images come from the store's
  /// website.
  static const List<BrandEntry> brands = [
    BrandEntry('Chiquita', 'assets/brands/brand_0.png', 'Chiquita'),
    BrandEntry('Zespri', 'assets/brands/brand_1.jpg', 'Zespri'),
    BrandEntry('Sebastiano', 'assets/brands/brand_2.jpg', 'Sebastiano'),
    BrandEntry('Jazz', 'assets/brands/brand_3.jpg', 'Jazz'),
    BrandEntry('Gems', 'assets/brands/brand_4.jpg', 'Gems'),
    BrandEntry('Fruitway', 'assets/brands/brand_5.jpg', 'Fruitway'),
    BrandEntry('Dazzle', 'assets/brands/brand_6.jpg', 'Dazzle'),
    BrandEntry('Thai Fresh', 'assets/brands/brand_7.png', 'Thai'),
    BrandEntry('Pink Lady', 'assets/brands/brand_8.png', 'Pink Lady'),
    BrandEntry('Juliet', 'assets/brands/brand_9.jpg', 'Juliet'),
  ];

  /// The "Offers" banners on Home, in row order.
  static const List<PromoEntry> promos = [
    PromoEntry('assets/promos/bulk.jpg', 'bulk-buy', 'Bulk Buy'),
    PromoEntry('assets/promos/deals.jpg', 'best-deals', 'Best Deals'),
    PromoEntry('assets/promos/essentials.jpg', 'deals-on-essentials',
        'Deals on Essentials'),
    PromoEntry('assets/promos/ambrosia.jpg', 'ambrosia', 'Ambrosia'),
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
