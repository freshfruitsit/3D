import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

/// Answers url_launcher calls with [result] and records the URLs asked for.
List<String> mockLauncher(WidgetTester tester, {required bool result}) {
  final launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
    call,
  ) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return result;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _launcher,
      null,
    ),
  );
  return launched;
}

void main() {
  final products = sampleProducts();
  final kiwi = products[0]; // 500 GM 19.95
  final beef = products[1]; // 62.50, was 115.00

  group('CartScreen', () {
    testWidgets('empty state offers a way back to shopping', (tester) async {
      final shell = ShellController()..select(AppTab.cart);
      await pumpScreen(tester, const CartScreen(), shell: shell);

      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('Checkout'), findsNothing);

      await tester.tap(find.text('Start shopping'));
      await tester.pump();
      expect(shell.tab, AppTab.home);
    });

    testWidgets('shows rows, count, sale price and subtotal', (tester) async {
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0]);
      await pumpScreen(tester, const CartScreen(), cart: cart);

      expect(find.text('3 items'), findsOneWidget);
      expect(find.text(kiwi.title), findsOneWidget);
      expect(find.text('500 GM · \u20C3 19.95 each'), findsOneWidget);
      expect(find.text('\u20C3 39.90'), findsOneWidget); // kiwi line total
      expect(find.text('\u20C3 62.50'), findsOneWidget); // beef line total
      expect(find.text('115.00'), findsOneWidget); // struck old line total
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('\u20C3 102.40'), findsOneWidget);
      expect(
        find.text('Delivery and taxes are calculated at checkout.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('stepper changes quantity and the bin removes the line', (
      tester,
    ) async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(tester, const CartScreen(), cart: cart);

      expect(find.text('1 item'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(cart.quantityOf(kiwi.variants[0].id), 2);
      expect(find.text('2 items'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(cart.isEmpty, isTrue);
      expect(find.text('Your cart is empty'), findsOneWidget);
    });

    testWidgets('stepper buttons are 44px touch targets', (tester) async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0], quantity: 2);
      await pumpScreen(tester, const CartScreen(), cart: cart);
      final size = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.remove),
          matching: find.byType(InkResponse),
        ),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('long cart scrolls and keeps the summary on screen', (
      tester,
    ) async {
      final cart = CartStore();
      for (final p in products) {
        for (final v in p.variants) {
          cart.add(p, v);
        }
      }
      await pumpScreen(tester, const CartScreen(), cart: cart);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        find.widgetWithText(FilledButton, 'Checkout'),
      );
      expect(button.bottom, lessThanOrEqualTo(844 - 88));
    });

    testWidgets('Checkout opens the cart permalink and keeps the cart', (
      tester,
    ) async {
      final launched = mockLauncher(tester, result: true);
      final cart = CartStore()..add(kiwi, kiwi.variants[0], quantity: 2);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
      await tester.pumpAndSettle();

      // No WebView in tests: the browser fallback takes over. The link
      // carries the website's delivery cart attributes.
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched, [
        'https://testtfm.myshopify.com/cart/${kiwi.variants[0].id}:2'
            '?attributes%5BDelivery%20mode%5D=Fresh%20Market'
            '&attributes%5BDelivery%20area%5D=Business%20Bay%2C%20Dubai'
            '&attributes%5BDelivery%20promise%5D=Today%20within%206%20hours'
            '&attributes%5BDelivery%20pin%5D=25.18500%2C55.26500',
      ]);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);

      await tester.tap(find.text('Back to cart'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(cart.itemCount, 2);
    });
  });

  group('CheckoutScreen', () {
    final url = Uri.parse('https://testtfm.myshopify.com/cart/2001:1');

    testWidgets('says so when no browser can be opened, and retries', (
      tester,
    ) async {
      final launched = mockLauncher(tester, result: false);
      await pumpScreen(tester, CheckoutScreen(url: url));
      await tester.pumpAndSettle();

      expect(find.text('Could not open checkout'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(launched.length, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountScreen', () {
    testWidgets('shows the sign-in card with a disabled button', (
      tester,
    ) async {
      await pumpScreen(tester, const AccountScreen());

      expect(find.text('Account'), findsOneWidget);
      expect(
        find.text('Sign in to see your orders and saved addresses'),
        findsOneWidget,
      );
      expect(
        find.text('Sign-in is not available in this version.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sign in'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('Favourites row shows the count and opens the list', (
      tester,
    ) async {
      final favourites = FavouritesStore()
        ..toggle(kiwi)
        ..toggle(beef);
      await pumpScreen(tester, const AccountScreen(), favourites: favourites);

      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();
      expect(find.text(kiwi.title), findsOneWidget);
      expect(find.text(beef.title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('design', () {
    testWidgets('cart lines: green steppers, hairlines between, AED for '
        'screen readers', (tester) async {
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
      );

      final steppers = tester.widgetList<QuantityStepper>(
        find.byType(QuantityStepper),
      );
      expect(steppers, hasLength(2));
      for (final stepper in steppers) {
        expect(stepper.style, QuantityStepperStyle.solid);
      }
      // One hairline between the two lines (none after the last).
      expect(find.byType(Divider), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('500 GM · \u20C3 19.95 each'))
            .semanticsLabel,
        '500 GM, AED 19.95 each',
      );
      expect(find.bySemanticsLabel('AED 102.40'), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-delivery')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Checkout'),
        ).style,
        isNull, // the theme's green buying button
      );
    });

    testWidgets('the empty cart offers an ink outlined Start shopping',
        (tester) async {
      await pumpScreen(tester, const CartScreen());
      expect(
        find.widgetWithText(OutlinedButton, 'Start shopping'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('Sign in is ink, not the green buying button',
        (tester) async {
      await pumpScreen(tester, const AccountScreen());
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sign in'),
      );
      expect(
        button.style!.backgroundColor!.resolve(const <WidgetState>{}),
        AppColors.ink,
      );
    });

    testWidgets('checkout: a retry is ink, opening again is green',
        (tester) async {
      final url = Uri.parse('https://testtfm.myshopify.com/cart/2001:1');
      mockLauncher(tester, result: false);
      await pumpScreen(tester, CheckoutScreen(url: url));
      await tester.pumpAndSettle();
      final retry = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Try again'),
      );
      expect(
        retry.style!.backgroundColor!.resolve(const <WidgetState>{}),
        AppColors.ink,
      );

      mockLauncher(tester, result: true);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      final again = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Open again'),
      );
      expect(again.style, isNull);
    });

    testWidgets('no overflow at 360dp and text scale 1.3', (tester) async {
      final cart = CartStore();
      for (final p in products) {
        for (final v in p.variants) {
          cart.add(p, v, quantity: 12);
        }
      }
      final favourites = FavouritesStore()..toggle(kiwi);
      for (final screen in [const CartScreen(), const AccountScreen()]) {
        await pumpScreen(
          tester,
          screen,
          cart: cart,
          favourites: favourites,
          delivery: testDelivery(mode: DeliveryMode.express),
        );
        tester.view.physicalSize = const Size(1080, 2340);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$screen');
      }
    });
  });
}
