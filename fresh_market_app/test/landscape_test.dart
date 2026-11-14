import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/home_screen.dart';
import 'package:fresh_market_app/screens/intro_screen.dart';
import 'package:fresh_market_app/screens/location_screen.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/widgets/ask_button.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'intro_test.dart' show FakeIntroPlayer;
import 'support/test_app.dart';

/// The app is not locked to portrait (WCAG 1.3.4): on a phone turned on
/// its side, 844x390, every screen still fits and scrolls.
const Size _landscape = Size(844, 390);

void _useLandscape(WidgetTester tester) {
  tester.view.physicalSize = _landscape * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Scrolls [scrollable] to its end in steps, failing on any overflow.
Future<void> _scrollThrough(WidgetTester tester, Finder scrollable) async {
  for (var i = 0; i < 40; i++) {
    final position = tester.state<ScrollableState>(scrollable).position;
    if (position.pixels >= position.maxScrollExtent) break;
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'scrolled $i times');
  }
  final position = tester.state<ScrollableState>(scrollable).position;
  expect(position.pixels, position.maxScrollExtent);
}

Widget _app({
  CartStore? cart,
  DeliveryStore? delivery,
  bool showIntro = false,
}) => FreshMarketApp(
  api: FakeShopifyApi.sample(),
  cart: cart ?? CartStore(),
  favourites: FavouritesStore(),
  deliveryStore: delivery,
  locationServices: testLocationServices(),
  showIntro: showIntro,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Home: the header scrolls away, the bar fits, nothing '
      'overflows', (tester) async {
    _useLandscape(tester);
    await tester.pumpWidget(_app(delivery: testDelivery()));
    await _settle(tester);
    expect(tester.takeException(), isNull);

    // The floating bar and the Ask button sit inside the short screen.
    final bar = tester.getRect(find.byType(FloatingNavBar));
    expect(bar.bottom, lessThanOrEqualTo(_landscape.height));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(_landscape.width));
    final ask = tester.getRect(find.byType(AskButton));
    expect(ask.bottom, lessThanOrEqualTo(bar.top));
    expect(ask.top, greaterThan(0));
    for (final tab in AppTab.values) {
      expect(
        find.descendant(
          of: find.byType(FloatingNavBar),
          matching: find.text(tab.label),
        ),
        findsOneWidget,
      );
    }

    // The header (wordmark, chip, search, switch) is not pinned: it
    // scrolls off and leaves the short screen to the products.
    final page = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    final search = find.byType(SearchFieldButton);
    expect(search, findsOneWidget);
    await tester.drag(page, const Offset(0, -400));
    await tester.pump();
    expect(
      search.evaluate().isEmpty || tester.getRect(search).bottom <= 0,
      isTrue,
    );
    await _scrollThrough(tester, page);
  });

  testWidgets('product detail scrolls under its sticky Add to cart bar', (
    tester,
  ) async {
    _useLandscape(tester);
    await tester.pumpWidget(_app(delivery: testDelivery()));
    await _settle(tester);

    final page = find
        .descendant(
          of: find.byType(HomeScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    final cards = find.byType(ProductCard);
    for (var i = 0; i < 20 && cards.evaluate().isEmpty; i++) {
      await tester.drag(page, const Offset(0, -150));
      await tester.pump();
    }
    // A card clear of the floating bar.
    final barTop = tester.getRect(find.byType(FloatingNavBar)).top;
    Finder? clear;
    for (var i = 0; i < 10 && clear == null; i++) {
      await tester.drag(page, const Offset(0, -100));
      await tester.pump();
      for (var c = 0; c < cards.evaluate().length; c++) {
        final centre = tester.getCenter(cards.at(c));
        if (centre.dy > 0 &&
            centre.dy < barTop - 60 &&
            centre.dx > 0 &&
            centre.dx < _landscape.width) {
          clear = cards.at(c);
          break;
        }
      }
    }
    await tester.tap(clear!);
    await _settle(tester);
    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final addToCart = find.textContaining('Add to cart');
    expect(addToCart, findsOneWidget);
    expect(
      tester.getRect(addToCart).bottom,
      lessThanOrEqualTo(_landscape.height),
    );
    await _scrollThrough(
      tester,
      find
          .descendant(
            of: find.byType(ProductDetailScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  });

  testWidgets('cart: lines scroll and Checkout stays reachable', (
    tester,
  ) async {
    _useLandscape(tester);
    final cart = CartStore();
    for (final product in sampleProducts()) {
      final variant = product.defaultVariant!;
      if (variant.available) cart.add(product, variant, quantity: 2);
    }
    await tester.pumpWidget(_app(cart: cart, delivery: testDelivery()));
    await _settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(FloatingNavBar),
        matching: find.text(AppTab.cart.label),
      ),
    );
    await _settle(tester);
    expect(find.byType(CartScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    final list = find
        .descendant(
          of: find.byType(CartScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await _scrollThrough(tester, list);
    final checkout = find.textContaining('Checkout');
    expect(checkout, findsWidgets);
    final rect = tester.getRect(checkout.last);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(_landscape.height));
  });

  testWidgets('the first-launch location gate fits and an area can be '
      'picked', (tester) async {
    _useLandscape(tester);
    final delivery = DeliveryStore(refreshEvery: null);
    await tester.pumpWidget(_app(delivery: delivery));
    await _settle(tester);
    expect(find.byType(LocationScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, 'Business');
    await _settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(tester.takeException(), isNull);
    final row = find.descendant(
      of: find.byType(LocationScreen),
      matching: find.text('Business Bay'),
    );
    final list = find
        .descendant(
          of: find.byKey(const ValueKey('location-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(row, 100, scrollable: list);
    await tester.pump();
    await tester.tap(row.first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await _scrollThrough(tester, list);

    // The sticky green button stays on the short screen.
    final deliver = find.descendant(
      of: find.byType(FilledButton),
      matching: find.text('Deliver to Business Bay'),
    );
    expect(deliver, findsOneWidget);
    final button = tester.getRect(deliver);
    expect(button.bottom, lessThanOrEqualTo(_landscape.height));
    await tester.tap(deliver);
    await _settle(tester);
    expect(delivery.hasArea, isTrue);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the intro keeps Skip and Start shopping on screen', (
    tester,
  ) async {
    _useLandscape(tester);
    final player = FakeIntroPlayer();
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: IntroScreen(onDone: () => done++, playerFactory: () => player),
      ),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    for (final key in [IntroScreen.skipKey, IntroScreen.startKey]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(_landscape.height));
    }
    await tester.tap(find.byKey(IntroScreen.startKey));
    expect(done, 1);
  });
}
