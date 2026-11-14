import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/widgets/state_views.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

List<String> searches(FakeShopifyApi api) =>
    api.calls.where((c) => c.startsWith('search(')).toList();

Future<void> type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Future<void> settleSearch(WidgetTester tester) async {
  await tester.pump(SearchScreen.debounce);
  await tester.pump();
}

void main() {
  testWidgets('starts focused with the popular chips and no request',
      (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const SearchScreen(), api: api);
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isTrue);
    for (final term in ['Strawberry', 'Avocado', 'Lamb', 'Bouquet']) {
      expect(find.text(term), findsOneWidget);
    }
    expect(api.calls, isEmpty);
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('typing searches once, after the pause', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const SearchScreen(), api: api);

    await type(tester, 'k');
    await tester.pump(const Duration(milliseconds: 100));
    await type(tester, 'ki');
    await tester.pump(const Duration(milliseconds: 100));
    await type(tester, 'kiwi');
    expect(searches(api), isEmpty);

    await settleSearch(tester);
    expect(searches(api), ['search(kiwi)']);
    expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);
    expect(find.text('500 g · New Zealand'), findsOneWidget);
    expect(find.text('\u20C3\u00A019.95'), findsOneWidget);
    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Popular searches'), findsNothing);
  });

  testWidgets('an initial query is searched straight away', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(
      tester,
      const SearchScreen(initialQuery: 'Zespri'),
      api: api,
    );
    await tester.pump();

    expect(searches(api), ['search(Zespri)']);
    expect(find.text('Zespri'), findsOneWidget); // the input
    expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);
    expect(find.byTooltip('Clear search'), findsOneWidget);
  });

  testWidgets('a popular chip fills the input and searches', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const SearchScreen(), api: api);

    await tester.tap(find.text('Bouquet'));
    await tester.pump();
    await tester.pump();

    expect(searches(api), ['search(Bouquet)']);
    expect(find.text('Pink Passion Flower Bouquet'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Bouquet',
    );
  });

  testWidgets('the clear button brings the chips back', (tester) async {
    await pumpScreen(tester, const SearchScreen(initialQuery: 'kiwi'));
    await tester.pump();
    expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    expect(find.text('Zespri Kiwi Sungold'), findsNothing);
    expect(find.text('Popular searches'), findsOneWidget);
  });

  testWidgets('rows add to the cart, and sold-out rows cannot', (tester) async {
    final cart = CartStore();
    await pumpScreen(tester, const SearchScreen(initialQuery: 'berry'), cart: cart);
    await tester.pump();

    // Blueberry (sold out) and Strawberry (250 GM sold out, 1 KG on sale).
    expect(find.text('2 results'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);
    expect(find.text('1 kg · South Africa'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Add Strawberry to cart'));
    await tester.pump();
    expect(cart.quantityOf(2009), 1);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('tapping a row opens the full product', (tester) async {
    await pumpScreen(tester, const SearchScreen(initialQuery: 'cucumber'));
    await tester.pump();

    await tester.tap(find.text('Cucumber'));
    await tester.pumpAndSettle();

    final detail = tester.widget<ProductDetailScreen>(
      find.byType(ProductDetailScreen),
    );
    expect(detail.product.handle, isNotEmpty);
    expect(detail.product.variants.length, 2);
  });

  testWidgets('no results offers to clear the search', (tester) async {
    await pumpScreen(tester, const SearchScreen(initialQuery: 'zzz'));
    await tester.pump();

    expect(find.byType(EmptyView), findsOneWidget);
    expect(find.text('No results for "zzz"'), findsOneWidget);

    await tester.tap(find.text('Clear search'));
    await tester.pump();
    expect(find.text('Popular searches'), findsOneWidget);
  });

  testWidgets('an error can be retried', (tester) async {
    final api = FakeShopifyApi.sample()
      ..error = const NetworkException('offline');
    await pumpScreen(tester, const SearchScreen(initialQuery: 'kiwi'), api: api);
    await tester.pump();

    expect(find.byType(ErrorView), findsOneWidget);

    api.error = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ErrorView), findsNothing);
    expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);
  });

  testWidgets('a slow answer to an older query is dropped', (tester) async {
    final api = FakeShopifyApi.sample()..delay = const Duration(seconds: 2);
    await pumpScreen(tester, const SearchScreen(), api: api);

    await type(tester, 'kiwi');
    await tester.pump(SearchScreen.debounce); // kiwi request leaves
    expect(find.byType(ProductCardSkeleton), findsWidgets);

    api.delay = Duration.zero;
    await type(tester, 'cucumber');
    await settleSearch(tester);
    expect(find.text('Cucumber'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3)); // kiwi answer arrives late
    expect(find.text('Cucumber'), findsOneWidget);
    expect(find.text('Zespri Kiwi Sungold'), findsNothing);
  });

  testWidgets('leaving while a search is pending is safe', (tester) async {
    await pumpScreen(tester, const SearchScreen());
    await type(tester, 'kiwi');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(SearchScreen.debounce);
    expect(tester.takeException(), isNull);
  });

  testWidgets('results are product cards in two columns', (tester) async {
    await pumpScreen(tester, const SearchScreen(initialQuery: 'berry'));
    await tester.pump();

    final cards = find.byType(ProductCard);
    expect(cards, findsNWidgets(2));
    expect(tester.getTopLeft(cards.at(0)).dy, tester.getTopLeft(cards.at(1)).dy);
    expect(tester.getTopLeft(cards.at(0)).dx, 16);
    expect(tester.getTopRight(cards.at(1)).dx, 390 - 16);
  });

  testWidgets('popular searches keep the page gutter', (tester) async {
    await pumpScreen(tester, const SearchScreen());
    await tester.pump();
    expect(tester.getTopLeft(find.text('Popular searches')).dx, 16);
  });

  testWidgets('no overflow at 360dp and text scale 1.3', (tester) async {
    await pumpScreen(
      tester,
      const SearchScreen(initialQuery: 'berry'),
      delivery: testDelivery(),
    );
    tester.view.physicalSize = const Size(1080, 2340);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await tester.pump();
    expect(find.byType(ProductCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
