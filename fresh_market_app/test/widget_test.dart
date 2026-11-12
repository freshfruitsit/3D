import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('app starts on Home and the bottom bar switches tabs',
      (tester) async {
    usePhoneSize(tester);
    final shell = ShellController();
    final cart = CartStore();
    final products = sampleProducts();
    cart.add(products[0], products[0].variants[0], quantity: 2);

    await tester.pumpWidget(FreshMarketApp(
      api: FakeShopifyApi.sample(),
      cart: cart,
      favourites: FavouritesStore(),
      shell: shell,
    ));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FloatingNavBar), findsOneWidget);
    final bar = find.byType(FloatingNavBar);
    for (final tab in AppTab.values) {
      expect(find.descendant(of: bar, matching: find.text(tab.label)),
          findsOneWidget);
    }
    // The cart badge shows the number of units.
    expect(find.descendant(of: bar, matching: find.text('2')), findsOneWidget);
    expect(shell.tab, AppTab.home);

    for (final tab in [AppTab.categories, AppTab.cart, AppTab.account]) {
      await tester.tap(find.descendant(of: bar, matching: find.text(tab.label)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(shell.tab, tab);
      expect(tester.widget<FloatingNavBar>(bar).current, tab);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('product card adds to the cart and turns into a stepper',
      (tester) async {
    final cart = CartStore();
    final products = sampleProducts();
    final beef = products[1];

    await pumpScreen(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => GridView(
            padding: const EdgeInsets.all(16),
            gridDelegate: ProductCard.gridDelegate(context),
            children: [for (final p in products) ProductCard(product: p)],
          ),
        ),
      ),
      cart: cart,
    );
    await tester.pump();

    expect(find.text('Australian Beef Cubes'), findsOneWidget);
    expect(find.text('Dhs. 62.50'), findsOneWidget);
    expect(find.text('115.00'), findsOneWidget);
    expect(find.text('-46%'), findsOneWidget);
    expect(find.text('New Zealand · 500 GM'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final beefCard = find.widgetWithText(ProductCard, 'Australian Beef Cubes');
    await tester.tap(
      find.descendant(of: beefCard, matching: find.byIcon(Icons.add)),
    );
    await tester.pump();
    expect(cart.quantityOf(beef.variants[0].id), 1);
    expect(
      find.descendant(of: beefCard, matching: find.byType(QuantityStepper)),
      findsOneWidget,
    );
    // At quantity 1 the minus is a bin, and it removes the line.
    await tester.tap(
      find.descendant(of: beefCard, matching: find.byIcon(Icons.delete_outline)),
    );
    await tester.pump();
    expect(cart.isEmpty, isTrue);
    expect(tester.takeException(), isNull);
  });
}
