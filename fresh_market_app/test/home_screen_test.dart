import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/data/catalog.dart';
import 'package:fresh_market_app/data/deals.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/screens/home_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/widgets/brand_tile.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';
import 'package:fresh_market_app/widgets/price_widgets.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/widgets/promo_row.dart';
import 'package:fresh_market_app/widgets/section_header.dart';
import 'package:fresh_market_app/widgets/state_views.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

const _settle = Duration(milliseconds: 500);

Finder get _page => find
    .descendant(of: find.byType(HomeScreen), matching: find.byType(Scrollable))
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 250, scrollable: _page);
  await tester.pump();
}

/// Scrolls the page until [target] is built, then puts it mid-screen.
Future<void> _centre(WidgetTester tester, Finder target) async {
  await _scrollTo(tester, target);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
}

/// A marked-down product that is not in "Today's Top Deals".
Product _platter(int id, int cents, int compareAt) => Product(
  id: id,
  title: 'Fruit Platter $id',
  handle: 'fruit-platter-$id',
  vendor: 'Ambrosia',
  productType: 'Platters',
  variants: [
    Variant(
      id: id + 100,
      title: 'Default Title',
      priceCents: cents,
      compareAtCents: compareAt,
    ),
  ],
  images: const [],
);

/// The sample store, where the whole catalogue ("all") also holds two
/// marked-down platters that no rail above "Best Deals" shows.
FakeShopifyApi _storeWithDeals() {
  final api = FakeShopifyApi.sample();
  api.collectionsByHandle[Deals.sourceHandle] = [
    ...sampleProducts(),
    _platter(1201, 25000, 28000), // 11%
    _platter(1202, 15000, 22000), // 32%
  ];
  return api;
}

int _railCalls(FakeShopifyApi api) =>
    api.calls.where((c) => c.startsWith('collectionProducts(')).length;

void main() {
  testWidgets('shows header, search, banners and the category grid', (
    tester,
  ) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();

    expect(find.text('Deliver to'), findsOneWidget);
    expect(find.text('Choose your area'), findsOneWidget);
    // The website's mode switch replaced the old "1Hr Express" button.
    expect(find.text('Fresh Market'), findsOneWidget);
    expect(find.text('Express'), findsOneWidget);
    expect(find.text('1Hr Express'), findsNothing);
    expect(find.byType(SearchFieldButton), findsOneWidget);
    expect(find.byKey(const ValueKey('banner-0')), findsOneWidget);
    for (var i = 0; i < Catalog.banners.length; i++) {
      expect(find.byKey(ValueKey('banner-dot-$i')), findsOneWidget);
    }
    expect(find.text('Shop By Category'), findsOneWidget);
    // Two rows of four on Home; "See all" opens the Categories tab with
    // every category.
    expect(find.byType(CategoryTile), findsNWidgets(8));
    expect(find.text('Melons'), findsNothing);
    expect(
      find.descendant(
        of: find.widgetWithText(SectionHeader, 'Shop By Category'),
        matching: find.text('See all'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('"See all" categories opens the Categories tab', (tester) async {
    final shell = ShellController();
    await pumpScreen(tester, const HomeScreen(), shell: shell);
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SectionHeader, 'Shop By Category'),
        matching: find.text('See all'),
      ),
    );
    await tester.pump();
    expect(shell.tab, AppTab.categories);
  });

  testWidgets(
    'sections come in the specified order, brands and offers between rails',
    (tester) async {
      final api = _storeWithDeals();
      await pumpScreen(tester, const HomeScreen(), api: api);
      await tester.pump();

      // Every rail asked for its own collection once.
      for (final rail in Catalog.rails) {
        expect(
          api.calls,
          contains('collectionProducts(${rail.handle}, page 1)'),
        );
      }
      expect(_railCalls(api), 5);

      const order = [
        "Today's Top Deals",
        'Best Deals',
        'Brands We Love',
        'Fresh Pick For You',
        'Offers',
        'Berries',
        'Seasonal Blooms',
        'Discover our fresh local products',
      ];
      // Headings are the slanted tags (a category tile is also "Berries").
      Finder heading(String title) => title == order.last
          ? find.text(title)
          : find.descendant(
              of: find.byType(SectionTag),
              matching: find.text(title),
            );
      final seen = <String>[];
      for (var i = 0; i < 40 && seen.length < order.length; i++) {
        for (final title in order) {
          if (!seen.contains(title) && heading(title).evaluate().isNotEmpty) {
            seen.add(title);
          }
        }
        await tester.drag(_page, const Offset(0, -250));
        await tester.pump();
      }
      expect(seen, order);
      expect(find.text('MADE IN UAE'), findsOneWidget);
      expect(find.text('Discover now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a rail shows product cards and See all opens its collection', (
    tester,
  ) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();

    await _scrollTo(tester, find.text("Today's Top Deals"));
    expect(find.byType(ProductCard), findsWidgets);
    expect(find.text('Zespri Kiwi Sungold'), findsWidgets);

    await tester.tap(find.text('See all').first);
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.handle, 'fresh-meat');
    expect(list.title, "Today's Top Deals");
  });

  testWidgets('rails show a skeleton while loading, then products', (
    tester,
  ) async {
    final api = FakeShopifyApi.sample()..delay = const Duration(seconds: 30);
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    await _scrollTo(tester, find.text("Today's Top Deals"));

    expect(
      find.byKey(const ValueKey('rail-loading-fresh-meat')),
      findsOneWidget,
    );
    expect(find.byType(ProductCard), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.byKey(const ValueKey('rail-loading-fresh-meat')), findsNothing);
    expect(find.byType(ProductCard), findsWidgets);
  });

  testWidgets('a failed rail offers a retry that loads only that rail', (
    tester,
  ) async {
    final api = FakeShopifyApi.sample()
      ..error = const NetworkException('offline');
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    await _scrollTo(tester, find.text("Today's Top Deals"));

    expect(find.byType(ErrorView), findsWidgets);
    expect(find.byType(ProductCard), findsNothing);
    // The rest of Home is still there.
    expect(find.text("Today's Top Deals"), findsOneWidget);

    api.error = null;
    final before = _railCalls(api);
    await tester.tap(find.text('Try again').first);
    await tester.pump();
    await tester.pump();
    expect(_railCalls(api), before + 1);
    expect(api.calls.last, 'collectionProducts(fresh-meat, page 1)');
    expect(find.byType(ProductCard), findsWidgets);
  });

  testWidgets('a collection the store does not have shows an error row', (
    tester,
  ) async {
    // No "berries" collection: only that rail fails.
    final api = FakeShopifyApi.sample(
      handles: const ['fresh-meat', 'all', 'best-sellers', 'ambrosia-flowers'],
    );
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    await _scrollTo(
      tester,
      find.descendant(
        of: find.byType(SectionTag),
        matching: find.text('Berries'),
      ),
    );
    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty collection hides its rail', (tester) async {
    final api = FakeShopifyApi.sample();
    api.collectionsByHandle['fresh-meat'] = [];
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    await _scrollTo(tester, find.text('Best Deals'));
    expect(find.text("Today's Top Deals"), findsNothing);
  });

  testWidgets('Best Deals shows real savings only, biggest first, never '
      "repeating Today's Top Deals", (tester) async {
    final api = _storeWithDeals();
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    // The whole catalogue is searched for products on sale.
    expect(api.calls, contains('collectionProducts(all, page 1)'));
    expect(
      api.calls,
      isNot(contains('collectionProducts(best-deals, page 1)')),
    );

    await _centre(tester, find.widgetWithText(SectionHeader, 'Best Deals'));
    final rail = find.byKey(const PageStorageKey('rail-all'));
    final cards = tester
        .widgetList<ProductCard>(
          find.descendant(of: rail, matching: find.byType(ProductCard)),
        )
        .toList();
    // Beef Cubes and Strawberry are on sale too, but the rail above
    // already shows them.
    expect(
      [for (final c in cards) c.product.title],
      ['Fruit Platter 1202', 'Fruit Platter 1201'],
    );
    for (final card in cards) {
      expect(
        find.descendant(
          of: find.byWidget(card),
          matching: find.byType(SalePill),
        ),
        findsOneWidget,
      );
    }

    // "See all" opens every product on sale, biggest saving first.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SectionHeader, 'Best Deals'),
        matching: find.text('See all'),
      ),
    );
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.handle, Deals.sourceHandle);
    expect(list.onSaleOnly, isTrue);
    expect(list.title, 'Best Deals');
    await tester.pump();
    expect(find.text('Biggest saving'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull to refresh reloads all five rails', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    expect(_railCalls(api), 5);

    await tester.fling(_page, const Offset(0, 400), 1200);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(_railCalls(api), 10);
    expect(tester.takeException(), isNull);
  });

  /// The brand rail's own (sideways) scroll view.
  Finder brandRail() => find
      .descendant(of: find.byType(BrandRail), matching: find.byType(Scrollable))
      .first;

  /// Scrolls Home to the brands, then the brand rail to brand [i].
  Future<void> showBrand(WidgetTester tester, int i) async {
    await _centre(tester, find.byType(BrandRail));
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('brand-$i')),
      BrandRail.tileWidth,
      scrollable: brandRail(),
    );
    await tester.pump();
  }

  testWidgets('brands sit in one sideways row, the next one peeking', (
    tester,
  ) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await _centre(tester, find.byType(BrandRail));

    const labels = [
      'Chiquita', 'Zespri', 'Sebastiano', 'Jazz', 'Gems', //
      'Fruitway', 'Dazzle', 'Thai Fresh', 'Pink Lady', 'Juliet',
    ];
    const files = [
      'brand_0.png', 'brand_1.jpg', 'brand_2.jpg', 'brand_3.jpg', //
      'brand_4.jpg', 'brand_5.jpg', 'brand_6.jpg', 'brand_7.png',
      'brand_8.png', 'brand_9.jpg',
    ];

    // One row: 80 wide tiles, 12 apart, from the gutter; the fifth peeks
    // in at the right edge (a scroll cue), and no row is half empty.
    Rect rect(int i) => tester.getRect(find.byKey(ValueKey('brand-$i')));
    expect(rect(0).left, 16);
    expect(rect(0).width, BrandRail.tileWidth);
    expect(rect(1).left, 16 + BrandRail.tileWidth + BrandRail.gap);
    expect(rect(3).top, rect(0).top);
    expect(rect(4).left, lessThan(390));
    expect(rect(4).right, greaterThan(390));

    // Every brand, its name below and its photo, in order.
    for (var i = 0; i < 10; i++) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('brand-$i')),
        BrandRail.tileWidth,
        scrollable: brandRail(),
      );
      final tile = find.byKey(ValueKey('brand-$i'));
      expect(
        find.descendant(of: tile, matching: find.text(labels[i])),
        findsOneWidget,
      );
      final image = tester.widget<Image>(
        find.descendant(of: tile, matching: find.byType(Image)),
      );
      expect(
        (image.image as AssetImage).assetName,
        'assets/brands/${files[i]}',
      );
      expect(image.fit, BoxFit.cover);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a brand tile: the photo fills a radius-14 square, the name '
      'below in 12/600 ink', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await _centre(tester, find.byType(BrandRail));

    final tile = find.byKey(const ValueKey('brand-0'));
    final rect = tester.getRect(tile);
    final image = tester.getRect(
      find.descendant(of: tile, matching: find.byType(Image)),
    );
    expect(image.width, moreOrLessEquals(BrandRail.tileWidth));
    expect(image.height, moreOrLessEquals(BrandRail.tileWidth));
    expect(image.left, moreOrLessEquals(rect.left));
    expect(image.top, moreOrLessEquals(rect.top));
    final clip = tester.widget<ClipRRect>(
      find.descendant(of: tile, matching: find.byType(ClipRRect)),
    );
    expect(clip.borderRadius, BorderRadius.circular(14));

    // Same tile look as the category grid: an off-white square.
    final square = tester.widget<DecoratedBox>(
      find.descendant(of: tile, matching: find.byType(DecoratedBox)).first,
    );
    expect((square.decoration as BoxDecoration).color, AppColors.subtle);
    // A short name: no word needs shrinking to fit the tile.
    final label = tester.widget<Text>(find.text('Jazz'));
    expect(
      tester.getRect(find.text('Chiquita')).top,
      greaterThan(image.bottom),
    );
    expect(label.style!.fontSize, 12);
    expect(label.style!.fontWeight, FontWeight.w600);
    expect(label.style!.color, AppColors.ink);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a brand tile opens Search pre-filled', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await showBrand(tester, 7);

    await tester.tap(find.text('Thai Fresh'));
    await tester.pump();
    await tester.pump(_settle);
    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialQuery, 'Thai');
  });

  testWidgets('brand tiles are labelled buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await showBrand(tester, 9);
    expect(find.bySemanticsLabel('Pink Lady'), findsOneWidget);
    expect(find.bySemanticsLabel('Juliet'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('offers row shows the four portrait banners in order', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await _centre(tester, find.byKey(const ValueKey('promo-0')));

    expect(find.text('Offers'), findsOneWidget);
    // No "See all" beside the Offers heading.
    final heading = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Offers'),
    );
    expect(heading.onViewAll, isNull);

    final row = find.descendant(
      of: find.byType(PromoRow),
      matching: find.byType(Scrollable),
    );
    const assets = ['bulk', 'deals', 'essentials', 'ambrosia'];
    const titles = [
      'Bulk Buy', 'Best Deals', 'Deals on Essentials', 'Ambrosia', //
    ];
    for (var i = 0; i < 4; i++) {
      final banner = find.byKey(ValueKey('promo-$i'));
      await tester.scrollUntilVisible(banner, 120, scrollable: row);
      await tester.pump();
      expect(tester.getSize(banner), const Size(156, 208));
      final ink = tester.widget<Ink>(
        find.descendant(of: banner, matching: find.byType(Ink)),
      );
      final decoration = ink.decoration! as BoxDecoration;
      expect(
        (decoration.image!.image as AssetImage).assetName,
        'assets/promos/${assets[i]}.jpg',
      );
      expect(decoration.image!.fit, BoxFit.cover);
      expect(find.bySemanticsLabel('Shop ${titles[i]}'), findsOneWidget);
    }
    final material = tester.widget<Material>(
      find.byKey(const ValueKey('promo-3')),
    );
    // A photo banner: radius 14, no border.
    expect(
      material.shape,
      const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    );
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  const offerTargets = [
    ('bulk-buy', 'Bulk Buy'),
    // "Deals of the day": the products really on sale.
    (Deals.sourceHandle, 'Best Deals'),
    ('deals-on-essentials', 'Deals on Essentials'),
    ('ambrosia', 'Ambrosia'),
  ];
  for (var i = 0; i < offerTargets.length; i++) {
    testWidgets('offer banner ${i + 1} opens ${offerTargets[i].$1}', (
      tester,
    ) async {
      await pumpScreen(tester, const HomeScreen());
      await tester.pump();
      final banner = find.byKey(ValueKey('promo-$i'));
      await _centre(tester, find.byKey(const ValueKey('promo-0')));
      await tester.scrollUntilVisible(
        banner,
        120,
        scrollable: find.descendant(
          of: find.byType(PromoRow),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      await tester.tap(banner);
      await tester.pump();
      await tester.pump(_settle);
      final list = tester.widget<ProductListScreen>(
        find.byType(ProductListScreen),
      );
      expect(list.handle, offerTargets[i].$1);
      expect(list.title, offerTargets[i].$2);
      expect(list.onSaleOnly, offerTargets[i].$1 == Deals.sourceHandle);
    });
  }

  testWidgets('search field opens Search with no query', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await tester.tap(find.byType(SearchFieldButton));
    await tester.pump();
    await tester.pump(_settle);
    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialQuery, isNull);
  });

  testWidgets('banners open their collections and advance by themselves', (
    tester,
  ) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();

    // Auto-play moves to the second banner.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('banner-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('banner-1')));
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.handle, 'vegetables');
  });

  testWidgets('Discover now opens the local UAE collection', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await _scrollTo(tester, find.text('Discover now'));
    await tester.tap(find.text('Discover now'));
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.handle, 'local-uae');
  });

  testWidgets('category tile opens its collection', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await tester.tap(find.text('Fruits'));
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.handle, 'fruits');
  });

  testWidgets('the header is white with a hairline under it, no colour bar', (
    tester,
  ) async {
    await pumpScreen(tester, const HomeScreen(), delivery: testDelivery());
    await tester.pump();

    final logo = find.byKey(const ValueKey('home-logo'));
    final image = tester.widget<Image>(logo);
    expect((image.image as AssetImage).assetName, Catalog.logoWideAsset);
    expect(image.semanticLabel, 'Fresh Market');
    final header = tester.widget<DecoratedBox>(
      find.ancestor(of: logo, matching: find.byType(DecoratedBox)).first,
    );
    final decoration = header.decoration as BoxDecoration;
    expect(decoration.color, AppColors.surface);
    expect(
      decoration.border,
      const Border(bottom: BorderSide(color: AppColors.hairline)),
    );
    // The header starts at the very top (behind the status bar) and the
    // delivery line is its last row.
    expect(tester.getRect(find.byWidget(header)).top, 0);
    expect(
      tester.getRect(find.byKey(const ValueKey('delivery-line'))).bottom,
      lessThan(tester.getRect(find.byWidget(header)).bottom),
    );
    expect(find.byKey(const ValueKey('delivery-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('banners have radius 16 and ink / grey dots', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    final banner = tester.widget<Material>(
      find.byKey(const ValueKey('banner-0')),
    );
    expect(banner.borderRadius, BorderRadius.circular(16));
    BoxDecoration dot(int i) =>
        tester
                .widget<AnimatedContainer>(
                  find.byKey(ValueKey('banner-dot-$i')),
                )
                .decoration!
            as BoxDecoration;
    expect(dot(0).color, AppColors.ink);
    expect(dot(1).color, isNot(AppColors.ink));
    expect(dot(1).color, isNot(AppColors.green));
  });

  testWidgets('sections are 28 apart, grids included', (tester) async {
    // Real text metrics: one-line tags, as on a phone.
    await loadAppFonts(tester);
    await pumpScreen(tester, const HomeScreen(), api: _storeWithDeals());
    await tester.pump();
    // The ink tag itself (its row is a 44pt touch target around it).
    Rect heading(String title) => tester.getRect(
      find.descendant(
        of: find.widgetWithText(SectionHeader, title),
        matching: find.byType(SectionTag),
      ),
    );

    // Banner dots, then "Shop By Category".
    await _centre(
      tester,
      find.widgetWithText(SectionHeader, 'Shop By Category'),
    );
    expect(
      heading('Shop By Category').top -
          tester.getRect(find.byKey(const ValueKey('banner-dot-0'))).bottom,
      moreOrLessEquals(AppDims.sectionGap),
    );
    // The lowest name of a grid's last row (a name may take two lines).
    double lastRowBottom(List<String> names) => names
        .map((n) => tester.getRect(find.text(n)).bottom)
        .reduce((a, b) => a > b ? a : b);

    // The last row of category names, then the first rail.
    await _centre(
      tester,
      find.widgetWithText(SectionHeader, "Today's Top Deals"),
    );
    expect(
      heading("Today's Top Deals").top -
          lastRowBottom(['Flowers', 'Hampers', 'Citrus', 'Mangoes']),
      moreOrLessEquals(AppDims.sectionGap, epsilon: 0.5),
    );
    // A rail of cards, then the next heading.
    await _centre(tester, find.widgetWithText(SectionHeader, 'Best Deals'));
    final topDeals = find.byKey(const PageStorageKey('rail-fresh-meat'));
    expect(
      heading('Best Deals').top - tester.getRect(topDeals).bottom,
      moreOrLessEquals(AppDims.sectionGap),
    );
    // The row of brand names, then "Fresh Pick For You".
    await _centre(
      tester,
      find.widgetWithText(SectionHeader, 'Fresh Pick For You'),
    );
    expect(
      heading('Fresh Pick For You').top -
          lastRowBottom(['Chiquita', 'Zespri', 'Sebastiano', 'Jazz']),
      moreOrLessEquals(AppDims.sectionGap, epsilon: 0.5),
    );
    // Heading to content: 12.
    final freshPick = find.byKey(const PageStorageKey('rail-best-sellers'));
    expect(
      tester.getRect(freshPick).top - heading('Fresh Pick For You').bottom,
      moreOrLessEquals(AppDims.headingGap),
    );
  });

  testWidgets('the Made in UAE card: white card, ink heading, ink outlined '
      'Discover now', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await _scrollTo(tester, find.text('Discover now'));

    expect(find.widgetWithText(OutlinedButton, 'Discover now'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Discover now'), findsNothing);
    final heading = tester.widget<Text>(
      find.text('Discover our fresh local products'),
    );
    expect(heading.style!.color, AppColors.ink);
    expect(heading.style!.fontSize, 18);
    final card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('Discover our fresh local products'),
            matching: find.byType(Container),
          )
          .last,
    );
    expect(card.decoration, AppDecor.card);
  });

  testWidgets('no overflow at 360dp with text scale 1.3, in every delivery '
      'state', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final at in [uaeTime(10), uaeTime(18, 30), uaeTime(23)]) {
      for (final mode in DeliveryMode.values) {
        for (final area in ['Business Bay', 'Jebel Ali', null]) {
          await pumpScreen(
            tester,
            const HomeScreen(),
            delivery: testDelivery(area: area, at: at, mode: mode),
          );
          tester.view.physicalSize = const Size(1080, 2340);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$at $mode $area');
          // The chip keeps to its share of the row, at the right end.
          final chip = tester.getRect(
            find.byKey(const ValueKey('location-chip')),
          );
          expect(chip.right, moreOrLessEquals(360 - 16));
          expect(chip.width, lessThanOrEqualTo(360 * 0.55 + 0.01));
        }
      }
    }
    // The whole page, last state.
    for (var i = 0; i < 25; i++) {
      await tester.drag(_page, const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('stays overflow-free with large text', (tester) async {
    usePhoneSize(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.drag(_page, const Offset(0, -400));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
