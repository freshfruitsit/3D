import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/my_details_screen.dart';
import 'package:fresh_market_app/screens/my_orders_screen.dart';
import 'package:fresh_market_app/screens/order_placed_screen.dart';
import 'package:fresh_market_app/services/customer_auth.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/profile_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import 'support/order_fakes.dart';
import 'support/test_app.dart';

// Fictional demo data only.
const sara = ContactDetails(
  firstName: 'Sara',
  lastName: 'Ahmed',
  mobile: '+971501234567',
  email: 'sara@example.com',
);

SavedAddress home() => SavedAddress(
  id: 'home',
  label: AddressLabel.home,
  area: DeliveryConfig.areaNamed('Business Bay')!,
  building: 'Bay Square, Building 5',
  flat: 'Flat 302',
  instructions: 'Call when you arrive',
);

ProfileStore filledProfile() => ProfileStore()
  ..saveContact(sara)
  ..saveAddress(home());

/// Records what is said to screen readers.
List<String> _announcements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        said.add((map['data']! as Map<Object?, Object?>)['message']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return said;
}

final _place = find.byKey(const ValueKey('checkout-place-order'));

FilledButton _placeButton(WidgetTester tester) =>
    tester.widget<FilledButton>(_place);

void main() {
  final products = sampleProducts();
  final kiwi = products[0]; // 500 GM 19.95, Express
  final beef = products[1]; // 62.50, Fresh Market only

  late FakeOrderServer server;
  late CartStore cart;
  late FakeOAuthClient oauth;

  setUp(() {
    server = FakeOrderServer();
    cart = CartStore()
      ..add(kiwi, kiwi.variants[0], quantity: 2)
      ..add(beef, beef.variants[0]);
    oauth = FakeOAuthClient();
  });

  /// Checkout for [cart] with the order server [server], signed in.
  Future<AccountSession> open(
    WidgetTester tester, {
    ProfileStore? profile,
    DeliveryStore? delivery,
    AccountSession? session,
    bool settle = true,
  }) async {
    final s = session ?? await signedInSession(client: oauth);
    await pumpScreen(
      tester,
      const CheckoutScreen(),
      cart: cart,
      profile: profile ?? filledProfile(),
      delivery: delivery ?? testDelivery(),
      session: s,
      orderApi: server.api(),
    );
    // A tall phone, so every section is built without scrolling.
    tester.view.physicalSize = const Size(1170, 4200);
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
    return s;
  }

  Future<void> placeOrder(WidgetTester tester) async {
    await tester.tap(_place);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('the checkout', () {
    testWidgets('sections in order, Cash on Delivery, the quote, the green '
        '52pt Place order with the total', (tester) async {
      await open(tester);
      // 2 x 19.95 + 62.50 = 102.40; delivery 25.00 below 200.
      expect(find.text(CheckoutScreen.orderCaption(3)), findsOneWidget);
      expect(find.text('Zespri Kiwi Sungold · 500 g'), findsOneWidget);
      expect(find.text('× 2'), findsOneWidget);
      expect(find.text('Australian Beef Cubes'), findsOneWidget);
      expect(find.text('⃃ 102.40'), findsOneWidget);
      expect(find.text(CheckoutScreen.freeDeliveryHint(9760)), findsOneWidget);
      expect(find.text(CheckoutScreen.vatNote), findsOneWidget);
      expect(find.text(CheckoutScreen.codTitle), findsOneWidget);
      expect(find.text(CheckoutScreen.codSubtitle), findsOneWidget);
      expect(find.text(CheckoutScreen.cashNote), findsOneWidget);
      expect(find.text('Place order · ⃃ 127.40'), findsOneWidget);

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('DELIVER TO'), lessThan(top('DELIVERY')));
      expect(top('DELIVERY'), lessThan(top('PAYMENT')));
      expect(top('PAYMENT'), lessThan(top('ORDER · 3 ITEMS')));

      final button = _placeButton(tester);
      expect(button.onPressed, isNotNull);
      expect(tester.getSize(_place).height, greaterThanOrEqualTo(52));
      // The theme's green buying button.
      expect(button.style, isNull);
      expect(
        Theme.of(tester.element(_place))
            .filledButtonTheme
            .style!
            .backgroundColor!
            .resolve(const <WidgetState>{}),
        AppColors.green,
      );
      // The quote asked for exactly what can be bought.
      expect(server.body(server.quoteRequests.single)['lines'], [
        {'variantId': 2001, 'quantity': 2},
        {'variantId': 2003, 'quantity': 1},
      ]);
    });

    testWidgets('while the quote loads: a placeholder and no Place order; '
        'then the totals', (tester) async {
      server.holdQuote = Completer<void>();
      await open(tester, settle: false);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('checkout-quote-loading')),
        findsOneWidget,
      );
      expect(_placeButton(tester).onPressed, isNull);
      expect(find.text('Place order'), findsOneWidget);
      server.holdQuote!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-order')), findsOneWidget);
      expect(_placeButton(tester).onPressed, isNotNull);
    });

    testWidgets('a quote that fails says so, with Try again', (tester) async {
      server.quoteStatus = 503;
      await open(tester);
      expect(
        find.byKey(const ValueKey('checkout-quote-error')),
        findsOneWidget,
      );
      expect(_placeButton(tester).onPressed, isNull);
      server.quoteStatus = null;
      await tester.tap(find.byKey(const ValueKey('checkout-quote-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-order')), findsOneWidget);
      expect(_placeButton(tester).onPressed, isNotNull);
    });

    testWidgets('free delivery from AED 200: "Free", no hint', (tester) async {
      cart.setQuantity(2003, 4); // 39.90 + 250.00
      await open(tester);
      expect(find.text(CheckoutScreen.free), findsWidgets);
      expect(find.textContaining('more for free delivery'), findsNothing);
      expect(find.text('Place order · ⃃ 289.90'), findsOneWidget);
    });

    testWidgets('missing name and mobile: said in place; Place order waits '
        'until they are added', (tester) async {
      final profile = ProfileStore()..saveAddress(home());
      await open(tester, profile: profile);
      expect(
        find.byKey(const ValueKey('checkout-need-details')),
        findsOneWidget,
      );
      expect(
        find.text('Add your name and mobile to place your order'),
        findsOneWidget,
      );
      expect(_placeButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('checkout-add-details')));
      await tester.pumpAndSettle();
      expect(find.byType(MyDetailsScreen), findsOneWidget);
      // Saved meanwhile (as My details does).
      profile.saveContact(sara);
      Navigator.of(tester.element(find.byType(MyDetailsScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-need-details')), findsNothing);
      expect(_placeButton(tester).onPressed, isNotNull);
    });
  });

  group('placing the order', () {
    testWidgets('201: the order goes with the address, the token and a key; '
        'the cart empties; Order placed says so', (tester) async {
      final said = _announcements(tester);
      await open(tester);
      // The driver's note can be changed.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-instructions')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('checkout-instructions')),
          matching: find.byType(EditableText),
        ),
        'Leave with the concierge',
      );
      await placeOrder(tester);

      final request = server.orderRequests.single;
      expect(request.headers['authorization'], 'Bearer access-1');
      expect(request.headers['idempotency-key'], hasLength(36));
      final body = server.body(request);
      expect(body['lines'], [
        {'variantId': 2001, 'quantity': 2},
        {'variantId': 2003, 'quantity': 1},
      ]);
      expect(body['address'], {
        'firstName': 'Sara',
        'lastName': 'Ahmed',
        'address1': 'Bay Square, Building 5',
        'address2': 'Flat 302',
        'city': 'Business Bay',
        'emirate': 'dubai',
        'phone': '+971501234567',
      });
      expect(body['delivery'], {
        'mode': 'market',
        'area': {
          'name': 'Business Bay',
          'emirate': 'dubai',
          'lat': 25.185,
          'lng': 55.265,
        },
        'promise': 'Today within 6 hours',
        'pin': '25.18500,55.26500',
      });
      expect(body['instructions'], 'Leave with the concierge');
      expect(body['expectedTotalFils'], 12740);

      expect(cart.isEmpty, isTrue);
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(find.text(OrderPlacedScreen.title), findsOneWidget);
      expect(find.text('Order #1001'), findsOneWidget);
      expect(find.text('Today within 6 hours'), findsOneWidget);
      expect(
        find.text('Home · Bay Square, Building 5 · Flat 302'),
        findsOneWidget,
      );
      expect(find.text('Pay ⃃ 127.40 on delivery'), findsOneWidget);
      expect(find.text(OrderPlacedScreen.cashLine), findsOneWidget);
      expect(
        find.text('A confirmation is on its way to sara@example.com'),
        findsOneWidget,
      );
      expect(
        said,
        contains(
          'Order placed. Order #1001. Pay AED 127.40 in cash on delivery.',
        ),
      );
    });

    testWidgets('while it is placed: the button says so and cannot be '
        'pressed twice; back waits', (tester) async {
      final hold = Completer<void>();
      server.orderAnswers.add((request) async {
        await hold.future;
        return server.created(request);
      });
      await open(tester);
      await tester.tap(_place);
      await tester.pump();
      await tester.pump();
      expect(find.text(CheckoutScreen.placing), findsOneWidget);
      expect(_placeButton(tester).onPressed, isNull);
      final pop = find.descendant(
        of: find.byType(CheckoutScreen),
        matching: find.byWidgetPredicate((w) => w is PopScope),
      );
      expect((tester.widget(pop) as PopScope).canPop, isFalse);
      await tester.tap(_place, warnIfMissed: false);
      await tester.pump();
      expect(server.orderRequests, hasLength(1));
      hold.complete();
      await tester.pumpAndSettle();
      expect(server.orderRequests, hasLength(1));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('409: "Your order changed", the line taken off struck '
        'through, new totals; placing again uses a new key', (tester) async {
      final said = _announcements(tester);
      await open(tester);
      server.soldOut.add(2003);
      server.orderAnswers.add(
        (_) => FakeOrderServer.json(409, {
          'error': 'quote_changed',
          'problems': [
            {'variantId': 2003, 'kind': 'sold_out', 'message': 'Sold out.'},
          ],
        }),
      );
      await placeOrder(tester);

      expect(cart.isEmpty, isFalse, reason: 'only a 201 empties the cart');
      expect(find.byType(OrderPlacedScreen), findsNothing);
      expect(find.byKey(const ValueKey('checkout-changed')), findsOneWidget);
      expect(find.text(CheckoutScreen.changedTitle), findsOneWidget);
      expect(
        find.textContaining('Australian Beef Cubes just sold out'),
        findsOneWidget,
      );
      expect(cart.lineOf(2003)!.available, isFalse);
      expect(
        find.byKey(const ValueKey('checkout-struck-2003')),
        findsOneWidget,
      );
      // New totals: 39.90 + 25.00.
      expect(find.text('Place order · ⃃ 64.90'), findsOneWidget);
      expect(said.any((s) => s.startsWith('Your order changed.')), isTrue);
      final firstKey = server.orderRequests.single.headers['idempotency-key'];

      await placeOrder(tester);
      final second = server.orderRequests.last;
      expect(second.headers['idempotency-key'], isNot(firstKey));
      expect(server.body(second)['lines'], [
        {'variantId': 2001, 'quantity': 2},
      ]);
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('quote problems on opening: less stock lowers the amount, '
        'said the same way', (tester) async {
      server.stock[2001] = 1;
      await open(tester);
      expect(find.byKey(const ValueKey('checkout-changed')), findsOneWidget);
      expect(
        find.textContaining('Only 1 of Zespri Kiwi Sungold left'),
        findsOneWidget,
      );
      expect(cart.quantityOf(2001), 1);
      // 19.95 + 62.50 + 25.00.
      expect(find.text('Place order · ⃃ 107.45'), findsOneWidget);
    });

    testWidgets('401: a fresh token once, then the same order with the same '
        'key', (tester) async {
      await open(tester);
      server.orderAnswers.add(
        (_) => FakeOrderServer.json(401, {'error': 'unauthorized'}),
      );
      await placeOrder(tester);
      expect(oauth.refreshCalls, 1);
      final requests = server.orderRequests;
      expect(requests, hasLength(2));
      expect(requests[0].headers['authorization'], 'Bearer access-1');
      expect(requests[1].headers['authorization'], 'Bearer refreshed-1');
      expect(
        requests[1].headers['idempotency-key'],
        requests[0].headers['idempotency-key'],
      );
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('401 again (or the refresh refused): sign in again, then '
        'Place order', (tester) async {
      final session = await open(tester);
      server.orderAnswers
        ..add((_) => FakeOrderServer.json(401, {}))
        ..add((_) => FakeOrderServer.json(401, {}));
      await placeOrder(tester);
      expect(find.text(CheckoutScreen.signInAgain), findsOneWidget);
      expect(cart.isEmpty, isFalse);

      oauth.refreshError = const RefreshRejected();
      await tester.tap(find.byKey(const ValueKey('checkout-problem-action')));
      await tester.pumpAndSettle();
      expect(oauth.authorizeCalls, 1);
      expect(session.signedIn, isTrue);
      expect(find.text(CheckoutScreen.signInAgain), findsNothing);
      await placeOrder(tester);
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('5xx: retried with the same key, then a calm error with Try '
        'again (the same key again)', (tester) async {
      final said = _announcements(tester);
      await open(tester);
      for (var i = 0; i < 3; i++) {
        server.orderAnswers.add(
          (_) => FakeOrderServer.json(503, {'retryable': true}),
        );
      }
      await placeOrder(tester);
      expect(server.orderRequests, hasLength(3));
      expect(
        find.textContaining("We couldn't place your order just now"),
        findsOneWidget,
      );
      expect(said.any((s) => s.contains("couldn't place your order")), isTrue);
      expect(cart.isEmpty, isFalse);

      await tester.tap(find.byKey(const ValueKey('checkout-problem-action')));
      await tester.pumpAndSettle();
      final keys = server.orderRequests
          .map((r) => r.headers['idempotency-key'])
          .toSet();
      expect(keys, hasLength(1), reason: 'one attempt, one key');
      expect(server.orderRequests, hasLength(4));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('422: the server\'s message, and the way to fix it', (
      tester,
    ) async {
      await open(tester);
      server.orderAnswers.add(
        (_) => FakeOrderServer.json(422, {
          'error': 'invalid',
          'field': 'address.phone',
          'message': 'Enter a UAE mobile like 050 123 4567.',
        }),
      );
      await placeOrder(tester);
      expect(
        find.text('Enter a UAE mobile like 050 123 4567.'),
        findsOneWidget,
      );
      expect(find.text('Edit details'), findsOneWidget);
      await tester.tap(find.text('Edit details'));
      await tester.pumpAndSettle();
      expect(find.byType(MyDetailsScreen), findsOneWidget);
    });

    testWidgets('429: wait a little; nothing retried by itself', (
      tester,
    ) async {
      await open(tester);
      server.orderAnswers.add(
        (_) => FakeOrderServer.json(429, {'retryAfterSeconds': 60}),
      );
      await placeOrder(tester);
      expect(server.orderRequests, hasLength(1));
      expect(find.textContaining('Wait a little'), findsOneWidget);
    });
  });

  group('Order placed', () {
    testWidgets('"View my orders" (ink) and "Continue shopping"', (
      tester,
    ) async {
      await open(tester);
      await placeOrder(tester);
      final view = find.byKey(const ValueKey('order-placed-view-orders'));
      expect(
        tester
            .widget<FilledButton>(view)
            .style!
            .backgroundColor!
            .resolve(const <WidgetState>{}),
        AppColors.ink,
      );
      expect(find.text(OrderPlacedScreen.continueShopping), findsOneWidget);
      await tester.tap(view);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MyOrdersScreen), findsOneWidget);
      expect(find.byType(OrderPlacedScreen), findsNothing);
    });

    testWidgets('fits at 200% text on a small phone', (tester) async {
      await loadAppFonts(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('checkout-instructions')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      await placeOrder(tester);
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('delivery and payment are radio rows with their state; '
        'captions are headers; targets are big enough', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      expect(
        tester.getSemantics(find.byKey(const ValueKey('checkout-mode-market'))),
        isSemantics(
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('checkout-mode-market')))
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(find.bySemanticsLabel('deliver to'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('checkout-change-address')))
            .height,
        greaterThanOrEqualTo(44),
      );
      handle.dispose();
    });
  });
}
