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

import 'support/order_fakes.dart';
import 'support/test_app.dart';

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
      expect(find.text('500 g · \u20C3\u00A019.95 each'), findsOneWidget);
      expect(find.text('\u20C3\u00A039.90'), findsOneWidget); // kiwi line total
      expect(find.text('\u20C3\u00A062.50'), findsOneWidget); // beef line total
      expect(find.text('115.00'), findsOneWidget); // struck old line total
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('\u20C3\u00A0102.40'), findsOneWidget);
      // UAE prices include VAT (the store's own cart says "Duties and
      // taxes included"): nothing suggests tax is added later.
      expect(
        find.text('Prices include VAT. Any delivery fee is shown at checkout.'),
        findsOneWidget,
      );
      expect(find.textContaining('taxes are calculated'), findsNothing);
      // The Checkout button carries the total.
      expect(find.text('Checkout · \u20C3\u00A0102.40'), findsOneWidget);
      expect(find.bySemanticsLabel('Checkout, AED 102.40'), findsOneWidget);
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
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.bottom, lessThanOrEqualTo(844 - 88));
    });

    testWidgets("Checkout opens the app's own checkout at the order "
        "server's prices and keeps the cart", (tester) async {
      final server = FakeOrderServer();
      final cart = CartStore()..add(kiwi, kiwi.variants[0], quantity: 2);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
        orderApi: server.api(),
      );

      await tester.tap(
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsOneWidget);
      final quote = server.body(server.quoteRequests.single);
      expect(quote['lines'], [
        {'variantId': kiwi.variants[0].id, 'quantity': 2},
      ]);
      expect(quote['delivery'], {
        'mode': 'market',
        'area': {
          'name': 'Business Bay',
          'emirate': 'dubai',
          'lat': 25.185,
          'lng': 55.265,
        },
      });
      // 39.90 + 25.00 delivery.
      expect(find.text('Place order · \u20C3\u00A064.90'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(cart.itemCount, 2);
    });
  });

  group('Express at checkout', () {
    Future<FakeOrderServer> openCheckout(
      WidgetTester tester,
      DeliveryStore delivery, {
      CartStore? cart,
    }) async {
      final server = FakeOrderServer();
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart ?? (CartStore()..add(kiwi, kiwi.variants[0])),
        delivery: delivery,
        orderApi: server.api(),
      );
      await tester.tap(
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return server;
    }

    String mode(FakeOrderServer server) =>
        (server.body(server.quoteRequests.last)['delivery'] as Map)['mode']
            as String;

    Finder row(String key) => find.byKey(ValueKey('checkout-mode-$key'));

    testWidgets('23:00 in Express: no question first; checkout keeps '
        'Express, says it is closed, and Fresh Market is one tap away', (
      tester,
    ) async {
      final delivery = testDelivery(
        at: uaeTime(23),
        mode: DeliveryMode.express,
      );
      final server = await openCheckout(tester, delivery);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(mode(server), 'express');
      expect(
        find.descendant(of: row('express'), matching: find.text('Closed')),
        findsOneWidget,
      );
      expect(
        find.text(
          'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
          'delivers tomorrow morning before 11 am.',
        ),
        findsOneWidget,
      );
      await tester.tap(row('market'));
      await tester.pumpAndSettle();
      expect(delivery.mode, DeliveryMode.market);
      expect(mode(server), 'market');
    });

    testWidgets('items not on Express: Fresh Market is selected and the '
        'Express row cannot be chosen', (tester) async {
      final delivery = testDelivery(mode: DeliveryMode.express);
      final server = await openCheckout(
        tester,
        delivery,
        cart: CartStore()
          ..add(kiwi, kiwi.variants[0])
          ..add(beef, beef.variants[0]),
      );
      await tester.pumpAndSettle();
      expect(delivery.mode, DeliveryMode.market);
      expect(mode(server), 'market');
      expect(
        find.text(
          'Not every item in your cart comes by Express, so Fresh Market '
          'delivery is selected.',
        ),
        findsOneWidget,
      );
      await tester.tap(row('express'));
      await tester.pumpAndSettle();
      expect(delivery.mode, DeliveryMode.market);
    });

    testWidgets('Express open: quoted as Express, the fee on its row', (
      tester,
    ) async {
      final delivery = testDelivery(
        at: uaeTime(10),
        mode: DeliveryMode.express,
      );
      final server = await openCheckout(tester, delivery);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(mode(server), 'express');
      expect(
        find.descendant(
          of: row('express'),
          matching: find.text('30–40 min · selected items only'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row('express'),
          matching: find.text('\u20C3\u00A025.00'),
        ),
        findsOneWidget,
      );
    });
  });

  group('CheckoutScreen', () {
    testWidgets('without an order server it says ordering is not available '
        'yet, and goes back to the cart', (tester) async {
      await pumpScreen(
        tester,
        const CheckoutScreen(),
        delivery: testDelivery(),
      );
      await tester.pumpAndSettle();
      expect(find.text(CheckoutScreen.unavailableTitle), findsOneWidget);
      expect(find.text(CheckoutScreen.unavailableMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('checkout-place-order')), findsNothing);
      expect(
        find.widgetWithText(OutlinedButton, CheckoutScreen.backToCart),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AccountScreen', () {
    testWidgets('signed out: "Sign in to order" first, with the ink '
        '"Sign in with email"; no "Coming soon" note', (tester) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        session: signedOutSession(),
      );

      expect(find.text('Account'), findsOneWidget);
      final card = find.byKey(const ValueKey('account-session'));
      expect(
        find.descendant(of: card, matching: find.text('Sign in to order')),
        findsOneWidget,
      );
      expect(
        find.text(
          "Use your email. We'll send you a 6-digit code, no password "
          'needed. You stay signed in on this phone.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      // First under the title, above the details card.
      expect(
        tester.getTopLeft(card).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('account-details'))).dy,
        ),
      );
      expect(find.text('Sign in to see your orders'), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(find.text('My orders'), findsNothing);
      expect(find.text(AccountScreen.signOutLabel), findsNothing);
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('Delivery location row shows the area and opens the picker', (
      tester,
    ) async {
      await pumpScreen(tester, const AccountScreen(), delivery: testDelivery());
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
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
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
        tester
            .widget<Text>(find.text('500 g · \u20C3\u00A019.95 each'))
            .semanticsLabel,
        '500 g, AED 19.95 each',
      );
      expect(find.bySemanticsLabel('AED 102.40'), findsOneWidget);
      expect(find.byKey(const ValueKey('cart-delivery')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.textContaining('Checkout · '),
                matching: find.byType(FilledButton),
              ),
            )
            .style,
        isNull, // the theme's green buying button
      );
    });

    testWidgets('the empty cart offers the green Start shopping', (
      tester,
    ) async {
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

    testWidgets('Account has no green: "Sign in with email" is ink', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        session: signedOutSession(),
      );
      final button = find.widgetWithText(FilledButton, 'Sign in with email');
      expect(button, findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      final material = tester.widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.ink);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(find.byKey(const ValueKey('sign-in-coming-soon')), findsNothing);
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
