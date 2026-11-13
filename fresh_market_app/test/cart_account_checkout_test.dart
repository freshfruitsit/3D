import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/location_screen.dart';
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
      // Size first, normalised; the unit price once there are two.
      expect(find.text('500 g · \u20C3 19.95 each'), findsOneWidget);
      expect(find.text('\u20C3 39.90'), findsOneWidget); // kiwi line total
      expect(find.text('\u20C3 62.50'), findsOneWidget); // beef line total
      expect(find.text('115.00'), findsOneWidget); // struck old line total
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('\u20C3 102.40'), findsOneWidget);
      // UAE prices include VAT (the store's own cart says "Duties and
      // taxes included"): nothing suggests tax is added later.
      expect(
        find.text('Prices include VAT. Any delivery fee is shown at checkout.'),
        findsOneWidget,
      );
      expect(find.textContaining('taxes are calculated'), findsNothing);
      // The Checkout button carries the total.
      expect(find.text('Checkout · \u20C3 102.40'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Checkout, AED 102.40'),
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
        find.ancestor(of: find.textContaining('Checkout · '), matching: find.byType(FilledButton)),
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

      await tester.tap(find.ancestor(of: find.textContaining('Checkout · '), matching: find.byType(FilledButton)));
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

  group('Express closed at checkout', () {
    Future<List<String>> openCheckout(
      WidgetTester tester,
      DeliveryStore delivery,
    ) async {
      final launched = mockLauncher(tester, result: true);
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: delivery,
      );
      await tester.tap(
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
      // The button spins while the question is open: no pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return launched;
    }

    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    testWidgets('23:00 in Express: asked first; Fresh Market goes to the '
        'store as Fresh Market', (tester) async {
      final delivery = testDelivery(
        at: uaeTime(23),
        mode: DeliveryMode.express,
      );
      final launched = await openCheckout(tester, delivery);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(inDialog('Express is closed'), findsOneWidget);
      expect(
        inDialog(
          'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
          'delivers tomorrow morning before 11 am.',
        ),
        findsOneWidget,
      );

      await tester.tap(inDialog('Switch to Fresh Market'));
      await tester.pumpAndSettle();
      expect(delivery.mode, DeliveryMode.market);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched.single, contains('Delivery%20mode%5D=Fresh%20Market'));
    });

    testWidgets('keeping Express checks out as before', (tester) async {
      final delivery = testDelivery(
        at: uaeTime(23),
        mode: DeliveryMode.express,
      );
      final launched = await openCheckout(tester, delivery);
      await tester.tap(inDialog('Keep Express'));
      await tester.pumpAndSettle();
      expect(delivery.mode, DeliveryMode.express);
      expect(launched.single, contains('Delivery%20mode%5D=Express'));
    });

    testWidgets('Express open: no question', (tester) async {
      final delivery = testDelivery(at: uaeTime(10), mode: DeliveryMode.express);
      final launched = await openCheckout(tester, delivery);
      expect(find.byType(AlertDialog), findsNothing);
      expect(launched.single, contains('Delivery%20mode%5D=Express'));
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
    testWidgets('shows the sign-in card with a Coming soon tag, not a '
        'dead button', (tester) async {
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
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('Delivery location row shows the area and opens the picker', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        delivery: testDelivery(),
      );
      final row = find.byKey(const ValueKey('account-location'));
      expect(
        find.descendant(of: row, matching: find.text('Delivery location')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Business Bay, Dubai')),
        findsOneWidget,
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(LocationScreen), findsOneWidget);
    });

    testWidgets('without an area the row asks for one', (tester) async {
      await pumpScreen(tester, const AccountScreen());
      expect(find.text('Choose your area'), findsOneWidget);
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

    testWidgets('Help & contact opens the store\'s phone, email and contact '
        'page', (tester) async {
      final opened = <Uri>[];
      var result = true;
      await pumpScreen(
        tester,
        AccountScreen(
          launcher: (uri) async {
            opened.add(uri);
            return result;
          },
        ),
      );

      // A 56pt row under "Watch the intro again", with the real contacts.
      final row = find.byKey(const ValueKey('account-help'));
      expect(
        find.descendant(of: row, matching: find.text('Help & contact')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('800 1 627538 · care@freshmarket.ae'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.support_agent_outlined),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(56));
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(tester.getTopLeft(find.text('Watch the intro again')).dy),
      );

      // The sheet: the website's contact text and the three links.
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text(AssistantBrain.contactText), findsOneWidget);
      expect(find.text('Call 800 1 627538'), findsOneWidget);
      expect(find.text('Email us'), findsOneWidget);
      expect(find.text('Contact page'), findsOneWidget);

      await tester.tap(find.text('Call 800 1 627538'));
      await tester.pumpAndSettle();
      expect(find.text('Email us'), findsNothing, reason: 'sheet closed');
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email us'));
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact page'));
      await tester.pumpAndSettle();
      expect(opened, [
        Uri.parse('tel:8001627538'),
        Uri.parse('mailto:care@freshmarket.ae'),
        Uri.parse('https://testtfm.myshopify.com/pages/contact'),
      ]);

      // Nothing can open it: the number to call instead.
      result = false;
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Call 800 1 627538'));
      await tester.pumpAndSettle();
      expect(
        find.text("Couldn't open the phone app. Call 8001627538 instead."),
        findsOneWidget,
      );
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
        tester.widget<Text>(find.text('500 g · \u20C3 19.95 each'))
            .semanticsLabel,
        '500 g, AED 19.95 each',
      );
      expect(find.bySemanticsLabel('AED 102.40'), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-delivery')), findsOneWidget);
      expect(
        tester.widget<FilledButton>(
          find.ancestor(of: find.textContaining('Checkout · '), matching: find.byType(FilledButton)),
        ).style,
        isNull, // the theme's green buying button
      );
    });

    testWidgets('the empty cart offers the green Start shopping',
        (tester) async {
      await pumpScreen(tester, const CartScreen());
      final button = find.widgetWithText(FilledButton, 'Start shopping');
      expect(button, findsOneWidget);
      // The theme's green buying button, not an ink outline.
      expect(tester.widget<FilledButton>(button).style, isNull);
      expect(find.byType(OutlinedButton), findsNothing);
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.green);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    });

    testWidgets('Account has no green and no dead Sign in button',
        (tester) async {
      await pumpScreen(tester, const AccountScreen());
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
      final tag = tester.widget<Container>(
        find.byKey(const ValueKey('sign-in-coming-soon')),
      );
      expect(
        (tag.decoration! as ShapeDecoration).color,
        AppColors.subtle,
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
