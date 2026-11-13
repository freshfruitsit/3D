import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/screens/assistant_screen.dart';
import 'package:fresh_market_app/screens/intro_screen.dart';
import 'package:fresh_market_app/widgets/ask_button.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('app starts on Home and the bottom bar switches tabs',
      (tester) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({});
    final shell = ShellController();
    final cart = CartStore();
    final products = sampleProducts();
    cart.add(products[0], products[0].variants[0], quantity: 2);

    await tester.pumpWidget(FreshMarketApp(
      api: FakeShopifyApi.sample(),
      cart: cart,
      favourites: FavouritesStore(),
      deliveryStore: testDelivery(),
      locationServices: testLocationServices(),
      shell: shell,
      showIntro: false,
    ));
    await tester.pump();
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

  testWidgets('every launch shows the intro, then Home', (tester) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({});
    Widget app() => FreshMarketApp(
          key: UniqueKey(),
          api: FakeShopifyApi.sample(),
          cart: CartStore(),
          favourites: FavouritesStore(),
          deliveryStore: testDelivery(),
          locationServices: testLocationServices(),
        );

    for (var launch = 0; launch < 2; launch++) {
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(IntroScreen), findsOneWidget);
      // The shop is loading underneath but cannot be seen or tapped.
      expect(find.byType(FloatingNavBar), findsNothing);
      expect(find.byType(FloatingNavBar, skipOffstage: false), findsOneWidget);

      await tester.tap(find.text('Start shopping'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(IntroScreen), findsNothing);
      expect(find.byType(FloatingNavBar), findsOneWidget);
    }
  });

  testWidgets('Ask button sits 12px above the bar, hides on Cart and with '
      'the keyboard, and opens the assistant', (tester) async {
    usePhoneSize(tester);
    SharedPreferences.setMockInitialValues({});
    final shell = ShellController();
    await tester.pumpWidget(FreshMarketApp(
      api: FakeShopifyApi.sample(),
      cart: CartStore(),
      favourites: FavouritesStore(),
      deliveryStore: testDelivery(),
      locationServices: testLocationServices(),
      shell: shell,
      showIntro: false,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final ask = find.byType(AskButton);
    final bar = find.byType(FloatingNavBar);
    expect(ask, findsOneWidget);
    final askRect = tester.getRect(ask);
    final barRect = tester.getRect(bar);
    final screen = tester.getSize(find.byType(AppShell));
    expect(barRect.top - askRect.bottom,
        moreOrLessEquals(AskButton.gapAboveNavBar));
    expect(screen.width - askRect.right, moreOrLessEquals(16));

    shell.select(AppTab.cart);
    await tester.pump(const Duration(milliseconds: 500));
    expect(ask, findsNothing);
    shell.select(AppTab.home);
    await tester.pump(const Duration(milliseconds: 500));
    expect(ask, findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    await tester.pump();
    expect(ask, findsNothing);
    expect(bar, findsNothing);
    tester.view.resetViewInsets();
    await tester.pump();

    await tester.tap(ask);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AssistantScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at the end of the Deals list no add control is under the '
      'Ask button', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final shell = ShellController();
    await tester.pumpWidget(FreshMarketApp(
      api: FakeShopifyApi.sample(),
      cart: CartStore(),
      favourites: FavouritesStore(),
      deliveryStore: testDelivery(),
      locationServices: testLocationServices(),
      shell: shell,
      showIntro: false,
    ));
    await tester.pump();
    shell.select(AppTab.deals);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Not hitTestable(): a control under the Ask button is exactly the
    // one that would be left out.
    final controls = find.byType(AddControl);
    expect(controls, findsWidgets);
    await tester.drag(find.byType(ProductCard).first, const Offset(0, -3000));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final askRect = tester.getRect(find.byType(AskButton));
    expect(controls, findsWidgets);
    for (final element in controls.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(rect.overlaps(askRect), isFalse, reason: '$rect under $askRect');
    }
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
