import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/models/money.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/price_widgets.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/widgets/state_views.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

/// [count] single-variant products; prices fall as the index rises, so the
/// cheapest product is on the last page.
List<Product> manyProducts(int count) => [
      for (var i = 0; i < count; i++)
        Product(
          id: 5000 + i,
          title: 'Item $i',
          handle: 'item-$i',
          vendor: 'Fresh Market',
          productType: 'Fruits',
          variants: [
            Variant(
              id: 9000 + i,
              title: 'Default Title',
              priceCents: 10000 - i * 100,
            ),
          ],
          images: const [],
        ),
    ];

/// A single-variant product at [cents], marked down from [compareAt] when
/// given.
Product dealProduct(int id, int cents, {int? compareAt, bool available = true}) =>
    Product(
      id: id,
      title: 'Deal $id',
      handle: 'deal-$id',
      vendor: 'Fresh Market',
      productType: 'Meat',
      variants: [
        Variant(
          id: 7000 + id,
          title: 'Default Title',
          priceCents: cents,
          compareAtCents: compareAt,
          available: available,
        ),
      ],
      images: const [],
    );

const fruits = ProductListScreen.collection(handle: 'fruits', title: 'Fruits');

List<String> cardTitles(WidgetTester tester) => [
      for (final card in tester.widgetList<ProductCard>(find.byType(ProductCard)))
        card.product.title,
    ];

/// The header scrolls away with the list; bring it back to read the count.
Future<void> scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, 30000));
  await tester.pump();
}

void main() {
  testWidgets('loads a collection into a grid with title and count',
      (tester) async {
    final api = FakeShopifyApi.sample()..delay = const Duration(seconds: 1);
    await pumpScreen(tester, fruits, api: api);

    // Card-shaped placeholders while the first page loads.
    expect(find.byType(ProductCardSkeleton), findsWidgets);
    expect(find.text('Fruits'), findsOneWidget);
    // Nothing was pushed, so there is no back arrow (Deals tab root).
    expect(find.byTooltip('Back'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byType(ProductCardSkeleton), findsNothing);
    expect(find.text('6 products'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);
    expect(find.text('Australian Beef Cubes'), findsOneWidget);
    // Two columns: the first two cards share a row.
    final cards = find.byType(ProductCard);
    expect(tester.getTopLeft(cards.at(0)).dy, tester.getTopLeft(cards.at(1)).dy);
    expect(tester.getTopLeft(cards.at(0)).dx, 16);
    expect(tester.getTopRight(cards.at(1)).dx, 390 - 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sort chip orders by price and back', (tester) async {
    await pumpScreen(tester, fruits);
    await tester.pump();

    expect(cardTitles(tester).first, 'Zespri Kiwi Sungold');

    await tester.tap(find.text('Featured'));
    await tester.pump();
    expect(find.text('Price: low to high'), findsOneWidget);
    // Cucumber 2.50, then Kiwi 19.95 (cheapest in-stock weight).
    expect(cardTitles(tester).take(2), ['Cucumber', 'Zespri Kiwi Sungold']);

    await tester.tap(find.text('Price: low to high'));
    await tester.pump();
    expect(find.text('Featured'), findsOneWidget);
    expect(cardTitles(tester).first, 'Zespri Kiwi Sungold');
  });

  testWidgets('loads the next page on scroll', (tester) async {
    final api = FakeShopifyApi(collections: {'fruits': manyProducts(60)});
    await pumpScreen(tester, fruits, api: api);
    await tester.pump();

    expect(find.text('24+ products'), findsOneWidget);
    expect(api.calls, ['collectionProducts(fruits, page 1)']);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump();
    expect(api.calls.last, 'collectionProducts(fruits, page 2)');
    await scrollToTop(tester);
    expect(find.text('48+ products'), findsOneWidget);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pump();
    await tester.pump();
    expect(api.calls.last, 'collectionProducts(fruits, page 3)');
    await scrollToTop(tester);
    expect(find.text('60 products'), findsOneWidget);

    // The last page was short: nothing more is requested.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('price sort loads the whole collection first', (tester) async {
    final api = FakeShopifyApi(collections: {'fruits': manyProducts(60)});
    await pumpScreen(tester, fruits, api: api);
    await tester.pump();

    await tester.tap(find.text('Featured'));
    await tester.pump();
    await tester.pump();

    expect(find.text('60 products'), findsOneWidget);
    // The cheapest product sits on the third page in store order.
    expect(cardTitles(tester).first, 'Item 59');
  });

  testWidgets('a failed price sort stays on Featured and can be retried',
      (tester) async {
    final api = FakeShopifyApi(collections: {'fruits': manyProducts(60)});
    await pumpScreen(tester, fruits, api: api);
    await tester.pump();

    api.error = const NetworkException('offline');
    await tester.tap(find.text('Featured'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Featured'), findsOneWidget);
    expect(find.textContaining('Could not sort by price'), findsOneWidget);
    expect(cardTitles(tester).first, 'Item 0');

    api.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Price: low to high'), findsOneWidget);
    expect(cardTitles(tester).first, 'Item 59');
  });

  testWidgets('shows an error with retry when the first load fails',
      (tester) async {
    final api = FakeShopifyApi.sample()
      ..error = const NetworkException('offline');
    await pumpScreen(tester, fruits, api: api);
    await tester.pump();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);
    expect(find.text('Featured'), findsNothing);

    api.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ErrorView), findsNothing);
    expect(find.text('6 products'), findsOneWidget);
  });

  testWidgets('a failed next page keeps the list and offers retry',
      (tester) async {
    final api = FakeShopifyApi(collections: {'fruits': manyProducts(60)});
    await pumpScreen(tester, fruits, api: api);
    await tester.pump();

    api.error = const NetworkException('offline');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pump();

    expect(find.text('Try again'), findsOneWidget);
    // No request storm while the error is showing.
    expect(api.calls.length, 2);

    api.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(api.calls.length, 3);
    await scrollToTop(tester);
    expect(find.text('48+ products'), findsOneWidget);
  });

  testWidgets('an empty collection offers a way back to shopping',
      (tester) async {
    final api = FakeShopifyApi(collections: {'fruits': const []});
    await pumpScreen(tester, fruits, api: api);
    await tester.pump();

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('Start shopping'), findsOneWidget);
    expect(find.text('Featured'), findsNothing);
  });

  testWidgets('favourites list shows the saved products and refreshes them',
      (tester) async {
    final api = FakeShopifyApi.sample();
    final favourites = FavouritesStore();
    final products = sampleProducts();
    favourites
      ..toggle(products[0])
      ..toggle(products[2]);

    await pumpScreen(
      tester,
      const ProductListScreen.favourites(),
      api: api,
      favourites: favourites,
    );
    await tester.pump();

    // Each saved product is reloaded once for today's price and stock;
    // no collection is loaded.
    expect(api.calls.toSet(),
        {'product(zespri-kiwi-sungold)', 'product(cucumber)'});
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('2 products'), findsOneWidget);
    // Newest favourite first.
    expect(cardTitles(tester), ['Cucumber', 'Zespri Kiwi Sungold']);

    favourites.remove(products[2].id);
    await tester.pump();
    expect(find.text('1 product'), findsOneWidget);

    favourites.remove(products[0].id);
    await tester.pump();
    expect(find.text('No favourites yet'), findsOneWidget);
    expect(find.text('Start shopping'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the back arrow when pushed', (tester) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => fruits),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductListScreen), findsNothing);
  });

  testWidgets('24/800 title and a white hairline sort pill', (tester) async {
    await pumpScreen(tester, fruits);
    await tester.pump();

    final title = tester.widget<Text>(find.text('Fruits'));
    expect(title.style, AppText.title);
    final pill = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Featured'),
        matching: find.byType(OutlinedButton),
      ),
    );
    final style = pill.style!;
    expect(
      style.backgroundColor!.resolve(const <WidgetState>{}),
      AppColors.surface,
    );
    expect(
      style.side!.resolve(const <WidgetState>{})!.color,
      AppColors.hairline,
    );
    expect(
      tester.getSize(find.byType(OutlinedButton)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('no overflow at 360dp and text scale 1.3', (tester) async {
    await pumpScreen(tester, fruits, delivery: testDelivery());
    tester.view.physicalSize = const Size(1080, 2340);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ProductCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('Deals', () {
    // The store's whole catalogue: three products really on sale among
    // plain ones, past the first page of 250 (one is sold out).
    List<Product> store() => [
          ...manyProducts(240),
          dealProduct(1, 4500, compareAt: 5200), // 13%
          dealProduct(2, 6250, compareAt: 11500), // 46%
          ...manyProducts(30).map((p) => dealProduct(p.id + 1000, 900)),
          dealProduct(3, 1950, compareAt: 2300), // 15%
          dealProduct(4, 1000, compareAt: 5000, available: false), // 80%
          dealProduct(5, 500, compareAt: 400), // "compare-at" below price
        ];

    testWidgets('the tab shows only real savings, biggest saving first',
        (tester) async {
      final api = FakeShopifyApi(collections: {'all': store()});
      await pumpScreen(tester, const ProductListScreen.deals(), api: api);
      await tester.pump();
      await tester.pump();

      // The whole catalogue was searched, in pages of 250.
      expect(api.calls, [
        'collectionProducts(all, page 1)',
        'collectionProducts(all, page 2)',
      ]);
      expect(find.text('Deals'), findsOneWidget);
      expect(find.text('4 products'), findsOneWidget);
      expect(find.text('Biggest saving'), findsOneWidget);
      // In stock first, by percentage; the sold-out 80% last.
      expect(cardTitles(tester), ['Deal 2', 'Deal 3', 'Deal 1', 'Deal 4']);
      // Every card in view shows its saving: the badge, the orange price
      // and the struck-through old price.
      for (final card in tester.widgetList<ProductCard>(
        find.byType(ProductCard),
      )) {
        final cardFinder = find.byWidget(card);
        expect(
          find.descendant(of: cardFinder, matching: find.byType(SalePill)),
          findsOneWidget,
          reason: card.product.title,
        );
        final price = tester.widget<PriceRow>(
          find.descendant(of: cardFinder, matching: find.byType(PriceRow)),
        );
        expect(price.oldPriceCents, greaterThan(price.priceCents));
        final shown = tester.widget<Text>(
          find.descendant(
            of: cardFinder,
            matching: find.text(formatMoney(price.priceCents)),
          ),
        );
        expect(shown.style!.color, AppColors.saving);
      }
      expect(find.text(SalePill.labelFor(46)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sort pill switches to price and back', (tester) async {
      final api = FakeShopifyApi(collections: {'all': store()});
      await pumpScreen(tester, const ProductListScreen.deals(), api: api);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Biggest saving'));
      await tester.pump();
      expect(find.text('Price: low to high'), findsOneWidget);
      expect(cardTitles(tester), ['Deal 4', 'Deal 3', 'Deal 1', 'Deal 2']);
      await tester.tap(find.text('Price: low to high'));
      await tester.pump();
      expect(cardTitles(tester).first, 'Deal 2');
    });

    testWidgets('nothing on sale: says so, never a made-up saving',
        (tester) async {
      final api = FakeShopifyApi(collections: {'all': manyProducts(12)});
      await pumpScreen(tester, const ProductListScreen.deals(), api: api);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ProductCard), findsNothing);
      expect(find.text('No offers right now'), findsOneWidget);
      expect(find.text('Start shopping'), findsOneWidget);
    });

    testWidgets('a failed load offers Try again', (tester) async {
      final api = FakeShopifyApi(collections: {'all': store()})
        ..error = const NetworkException('offline');
      await pumpScreen(tester, const ProductListScreen.deals(), api: api);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ErrorView), findsOneWidget);

      api.error = null;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(cardTitles(tester).first, 'Deal 2');
    });
  });
}
