import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/data/catalog.dart';
import 'package:fresh_market_app/screens/home_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
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

int _railCalls(FakeShopifyApi api) =>
    api.calls.where((c) => c.startsWith('collectionProducts(')).length;

void main() {
  testWidgets('shows header, search, banners and the category grid',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();

    expect(find.text('Deliver to'), findsOneWidget);
    expect(find.text('Choose your area'), findsOneWidget);
    expect(find.text('1Hr Express'), findsOneWidget);
    expect(find.byType(SearchFieldButton), findsOneWidget);
    expect(find.byKey(const ValueKey('banner-0')), findsOneWidget);
    for (var i = 0; i < Catalog.banners.length; i++) {
      expect(find.byKey(ValueKey('banner-dot-$i')), findsOneWidget);
    }
    expect(find.text('Shop By Category'), findsOneWidget);
    expect(find.byType(CategoryTile), findsNWidgets(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sections come in the specified order, brands between rails',
      (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();

    // Every rail asked for its own collection once.
    for (final rail in Catalog.rails) {
      expect(api.calls, contains('collectionProducts(${rail.handle}, page 1)'));
    }
    expect(_railCalls(api), 5);

    const order = [
      "Today's Top Deals",
      'Best Deals',
      'Brands We Love',
      'Fresh Pick For You',
      'Berries',
      'Seasonal Blooms',
      'Discover our fresh local products',
    ];
    final seen = <String>[];
    for (var i = 0; i < 40 && seen.length < order.length; i++) {
      for (final title in order) {
        if (!seen.contains(title) && find.text(title).evaluate().isNotEmpty) {
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
  });

  testWidgets('a rail shows product cards and View all opens its collection',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();

    await _scrollTo(tester, find.text("Today's Top Deals"));
    expect(find.byType(ProductCard), findsWidgets);
    expect(find.text('Zespri Kiwi Sungold'), findsWidgets);

    await tester.tap(find.text('View all').first);
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
        find.byType(ProductListScreen));
    expect(list.handle, 'fresh-meat');
    expect(list.title, "Today's Top Deals");
  });

  testWidgets('rails show a skeleton while loading, then products',
      (tester) async {
    final api = FakeShopifyApi.sample()..delay = const Duration(seconds: 30);
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    await _scrollTo(tester, find.text("Today's Top Deals"));

    expect(find.byKey(const ValueKey('rail-loading-fresh-meat')), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);

    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(find.byKey(const ValueKey('rail-loading-fresh-meat')), findsNothing);
    expect(find.byType(ProductCard), findsWidgets);
  });

  testWidgets('a failed rail offers a retry that loads only that rail',
      (tester) async {
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

  testWidgets('a collection the store does not have shows an error row',
      (tester) async {
    // No "berries" collection: only that rail fails.
    final api = FakeShopifyApi.sample(handles: const [
      'fresh-meat',
      'best-deals',
      'best-sellers',
      'ambrosia-flowers',
    ]);
    await pumpScreen(tester, const HomeScreen(), api: api);
    await tester.pump();
    await _scrollTo(tester, find.text('Berries'));
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

  testWidgets('brands row lists the ten brands and opens Search pre-filled',
      (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await _scrollTo(tester, find.text('Brands We Love'));

    expect(find.text('Chiquita Bananas'), findsOneWidget);
    expect(find.text('Zespri Kiwi'), findsOneWidget);
    final image = tester.widget<Image>(find.descendant(
      of: find.byKey(const ValueKey('brand-0')),
      matching: find.byType(Image),
    ));
    expect((image.image as AssetImage).assetName, 'assets/brands/brand_0.png');
    expect(tester.getSize(find.byWidget(image)), const Size(104, 104));

    // The last brand is reachable by scrolling the row.
    final row = find.descendant(
      of: find.byKey(const PageStorageKey('brands')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('Juliet Apple'), 200,
        scrollable: row);
    await tester.drag(row, const Offset(-200, 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('brand-9')), findsOneWidget);

    await tester.tap(find.text('Juliet Apple'));
    await tester.pump();
    await tester.pump(_settle);
    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialQuery, 'Juliet');
  });

  testWidgets('search field opens Search with no query', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await tester.tap(find.byType(SearchFieldButton));
    await tester.pump();
    await tester.pump(_settle);
    final search = tester.widget<SearchScreen>(find.byType(SearchScreen));
    expect(search.initialQuery, isNull);
  });

  testWidgets('banners open their collections and advance by themselves',
      (tester) async {
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
        find.byType(ProductListScreen));
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
        find.byType(ProductListScreen));
    expect(list.handle, 'local-uae');
  });

  testWidgets('category tile opens its collection', (tester) async {
    await pumpScreen(tester, const HomeScreen());
    await tester.pump();
    await tester.tap(find.text('FRUITS'));
    await tester.pump();
    await tester.pump(_settle);
    final list = tester.widget<ProductListScreen>(
        find.byType(ProductListScreen));
    expect(list.handle, 'fruits');
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
