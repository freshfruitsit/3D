import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/models/order.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/my_details_screen.dart';
import 'package:fresh_market_app/screens/my_orders_screen.dart';
import 'package:fresh_market_app/screens/order_placed_screen.dart';
import 'package:fresh_market_app/services/customer_auth.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/order_api.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/profile_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      expect(find.text('⃃\u00A0102.40'), findsOneWidget);
      expect(find.text(CheckoutScreen.freeDeliveryHint(9760)), findsOneWidget);
      expect(find.text(CheckoutScreen.vatNote), findsOneWidget);
      expect(find.text(CheckoutScreen.codTitle), findsOneWidget);
      expect(find.text(CheckoutScreen.codSubtitle), findsOneWidget);
      expect(find.text(CheckoutScreen.cashNote), findsOneWidget);
      expect(find.text('Place order · ⃃\u00A0127.40'), findsOneWidget);

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
      // The quote's own words, not the order-placing ones.
      expect(
        find.text('Fresh Market is busy right now. Try again in a moment.'),
        findsOneWidget,
      );
      expect(find.textContaining('place your order'), findsNothing);
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
      expect(find.text('Place order · ⃃\u00A0289.90'), findsOneWidget);
    });

    test('quote failures are said for prices, not for placing', () {
      expect(
        CheckoutScreen.quoteErrorText(const OrderNetworkError()),
        "We couldn't get today's prices. Check your connection and try again.",
      );
      const busy = 'Fresh Market is busy right now. Try again in a moment.';
      expect(CheckoutScreen.quoteErrorText(const OrderRateLimited()), busy);
      expect(
        CheckoutScreen.quoteErrorText(
          const OrderServerError(503, retryable: true),
        ),
        busy,
      );
      expect(
        CheckoutScreen.quoteErrorText(
          const OrderInvalid(field: 'delivery.area', message: 'We do not '
              'deliver to this area yet.'),
        ),
        'We do not deliver to this area yet.',
      );
      expect(
        CheckoutScreen.quoteErrorText(const OrderServerError(400)),
        "We couldn't get today's prices. Try again in a moment.",
      );
    });

    testWidgets('no address for the area: said in place, with Add address; '
        'Place order waits', (tester) async {
      final profile = ProfileStore()..saveContact(sara);
      await open(tester, profile: profile);
      expect(
        find.byKey(const ValueKey('checkout-need-address')),
        findsOneWidget,
      );
      expect(find.text(CheckoutScreen.needAddressTitle), findsOneWidget);
      expect(
        find.text('Add your address to place your order'),
        findsOneWidget,
      );
      expect(_placeButton(tester).onPressed, isNull);
      expect(
        find.byKey(const ValueKey('checkout-add-address')),
        findsOneWidget,
      );
      // Added meanwhile (as the address page does): Place order is ready.
      profile.saveAddress(home());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('checkout-need-address')), findsNothing);
      expect(_placeButton(tester).onPressed, isNotNull);
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
      expect(find.text('Pay ⃃\u00A0127.40 on delivery'), findsOneWidget);
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
      expect(find.text('Place order · ⃃\u00A064.90'), findsOneWidget);
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
      expect(find.text('Place order · ⃃\u00A0107.45'), findsOneWidget);
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

    testWidgets('401 and the forced refresh refused: signed out, sign in '
        'again, then the order goes with the same key', (tester) async {
      final session = await open(tester);
      server.orderAnswers.add((_) => FakeOrderServer.json(401, {}));
      oauth.refreshError = const RefreshRejected();
      await placeOrder(tester);
      expect(oauth.refreshCalls, 1);
      expect(server.orderRequests, hasLength(1));
      expect(session.signedIn, isFalse);
      expect(find.text(CheckoutScreen.signInAgain), findsOneWidget);
      expect(cart.isEmpty, isFalse);

      oauth.refreshError = null;
      await tester.tap(find.byKey(const ValueKey('checkout-problem-action')));
      await tester.pumpAndSettle();
      expect(session.signedIn, isTrue);
      await placeOrder(tester);
      expect(server.orderRequests, hasLength(2));
      expect(
        server.orderRequests[1].headers['idempotency-key'],
        server.orderRequests[0].headers['idempotency-key'],
      );
      expect(server.orderRequests[1].headers['authorization'], 'Bearer access-1');
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
      // "Change" goes under the address, which keeps the card's width.
      expect(
        tester.getTopLeft(find.text('Change')).dy,
        greaterThan(tester.getBottomLeft(find.textContaining('Sara Ahmed')).dy),
      );
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

  group('never two orders, and never a stale total', () {
    /// A page with "Open checkout", which pushes checkout over it (so
    /// checkout can be closed and opened again).
    Future<AccountSession> host(WidgetTester tester) async {
      final session = await signedInSession(client: oauth);
      await pumpScreen(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CheckoutScreen(),
                  ),
                ),
                child: const Text('Open checkout'),
              ),
            ),
          ),
        ),
        cart: cart,
        profile: filledProfile(),
        delivery: testDelivery(),
        session: session,
        orderApi: server.api(),
      );
      tester.view.physicalSize = const Size(1170, 4200);
      await tester.pump();
      await tester.tap(find.text('Open checkout'));
      await tester.pumpAndSettle();
      return session;
    }

    void failThrice() {
      for (var i = 0; i < 3; i++) {
        server.orderAnswers.add(
          (_) => FakeOrderServer.json(503, {'retryable': true}),
        );
      }
    }

    Set<String?> keys() => {
      for (final r in server.orderRequests) r.headers['idempotency-key'],
    };

    testWidgets('a 5xx, then the note edited: Try again sends the same key '
        '(the first try may have gone through) with the new note', (
      tester,
    ) async {
      await open(tester);
      failThrice();
      await placeOrder(tester);
      expect(find.text(CheckoutScreen.tryAgain), findsOneWidget);
      expect(cart.pendingOrder, isNotNull);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('checkout-instructions')),
          matching: find.byType(EditableText),
        ),
        'Leave at the door',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('checkout-problem-action')));
      await tester.pumpAndSettle();
      expect(server.orderRequests, hasLength(4));
      expect(keys(), hasLength(1), reason: 'one order, one key');
      expect(
        server.body(server.orderRequests.last)['instructions'],
        'Leave at the door',
      );
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(cart.isEmpty, isTrue);
      expect(cart.pendingOrder, isNull);
    });

    testWidgets('a 5xx, then checkout closed and opened again: the same '
        'key', (tester) async {
      await host(tester);
      failThrice();
      await placeOrder(tester);
      expect(find.text(CheckoutScreen.tryAgain), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      await tester.tap(find.text('Open checkout'));
      await tester.pumpAndSettle();
      await placeOrder(tester);
      expect(server.orderRequests, hasLength(4));
      expect(keys(), hasLength(1));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('the key outlives a restart of the app (kept on the device)',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      cart = CartStore(prefs: prefs)
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0]);
      await open(tester);
      failThrice();
      await placeOrder(tester);
      final first = server.orderRequests.first.headers['idempotency-key'];

      // The app is closed and opened again: the cart is read back.
      cart = CartStore(prefs: prefs);
      expect(cart.pendingOrder?.key, first);
      await open(tester);
      await placeOrder(tester);
      expect(server.orderRequests.last.headers['idempotency-key'], first);
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(prefs.getString(CartStore.pendingOrderPrefsKey), isNull);
    });

    testWidgets('the 201 comes after checkout was closed: the cart is '
        'emptied all the same', (tester) async {
      await host(tester);
      final hold = Completer<void>();
      server.orderAnswers.add((request) async {
        await hold.future;
        return server.created(request);
      });
      await tester.tap(_place);
      await tester.pump();
      // Checkout goes (the app closed it) while the order is on its way.
      Navigator.of(tester.element(find.byType(CheckoutScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      hold.complete();
      await tester.pumpAndSettle();
      expect(cart.isEmpty, isTrue);
      expect(cart.pendingOrder, isNull);
    });

    testWidgets('signed in again as someone else: a new key', (tester) async {
      await open(tester);
      server.orderAnswers
        ..add((_) => FakeOrderServer.json(401, {}))
        ..add((_) => FakeOrderServer.json(401, {}));
      await placeOrder(tester);
      expect(find.text(CheckoutScreen.signInAgain), findsOneWidget);
      final first = server.orderRequests.first.headers['idempotency-key'];

      oauth.email = 'omar@example.com';
      oauth.refreshError = const RefreshRejected();
      await tester.tap(find.byKey(const ValueKey('checkout-problem-action')));
      await tester.pumpAndSettle();
      oauth.refreshError = null;
      await placeOrder(tester);
      final last = server.orderRequests.last;
      expect(last.headers['idempotency-key'], isNot(first));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
    });

    testWidgets('the key was another customer\'s (422 Idempotency-Key): a '
        'new key at once, and the order goes', (tester) async {
      await open(tester);
      server.orderAnswers.add(
        (_) => FakeOrderServer.json(422, {
          'error': 'invalid',
          'field': 'Idempotency-Key',
          'message': 'This Idempotency-Key was already used. Send a new one '
              'for a new order.',
        }),
      );
      await placeOrder(tester);
      expect(server.orderRequests, hasLength(2));
      expect(keys(), hasLength(2));
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      expect(find.textContaining('Idempotency'), findsNothing);
    });

    testWidgets('the key brings back an earlier order of another basket: '
        'said, the cart stays, the next try is a new order', (tester) async {
      final said = _announcements(tester);
      await open(tester);
      server.orderAnswers.add(
        (_) => http.Response(
          jsonEncode({
            'orderId': 'gid://shopify/Order/1000',
            'orderName': '#1000',
            'totalFils': 8750,
            'deliveryPromise': 'Today within 6 hours',
            'paymentMethod': 'Cash on Delivery',
          }),
          201,
          headers: {
            'content-type': 'application/json',
            'idempotent-replayed': 'true',
          },
        ),
      );
      await placeOrder(tester);
      expect(find.byType(OrderPlacedScreen), findsNothing);
      expect(cart.isEmpty, isFalse);
      expect(cart.pendingOrder, isNull);
      final line = CheckoutScreen.earlierOrderLine(
        const PlacedOrder(
          orderId: 'gid://shopify/Order/1000',
          orderName: '#1000',
          totalFils: 8750,
          deliveryPromise: '',
        ),
      );
      expect(find.text(line), findsOneWidget);
      expect(find.text(CheckoutScreen.viewOrders), findsOneWidget);
      expect(said, contains(line));
    });

    testWidgets('the last line sells out (409): struck through, "Everything '
        'in your order sold out", Back to cart, and no Place order', (
      tester,
    ) async {
      final said = _announcements(tester);
      cart = CartStore()..add(beef, beef.variants[0]);
      await open(tester);
      expect(find.text('Place order · ⃃ 87.50'), findsOneWidget);
      server.soldOut.add(2003);
      server.orderAnswers.add(
        (request) => FakeOrderServer.json(409, {
          'error': 'quote_changed',
          'problems': [
            {'variantId': 2003, 'kind': 'sold_out', 'message': 'Sold out.'},
          ],
          'quote': server.quoteFor(server.body(request)),
        }),
      );
      await placeOrder(tester);
      expect(cart.lineOf(2003)!.available, isFalse);
      expect(find.byKey(const ValueKey('checkout-sold-out')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('checkout-struck-2003')),
        findsOneWidget,
      );
      expect(find.text(CheckoutScreen.allSoldOut), findsOneWidget);
      expect(find.textContaining('87.50'), findsNothing);
      expect(find.text('Place order'), findsOneWidget);
      expect(_placeButton(tester).onPressed, isNull);
      expect(
        said.any((s) => s.contains(CheckoutScreen.allSoldOut)),
        isTrue,
      );
      // Nothing more is sent.
      await tester.tap(_place, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(server.orderRequests, hasLength(1));
      expect(
        find.byKey(const ValueKey('checkout-back-to-cart')),
        findsOneWidget,
      );
    });

    testWidgets('the same with no quote in the 409: no old total stays up',
        (tester) async {
      cart = CartStore()..add(beef, beef.variants[0]);
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
      expect(find.byKey(const ValueKey('checkout-sold-out')), findsOneWidget);
      expect(_placeButton(tester).onPressed, isNull);
      expect(find.textContaining('87.50'), findsNothing);
    });

    testWidgets('a price that changed (409 without a quote): the server\'s '
        'sentence, then the new price from the new quote', (tester) async {
      cart = CartStore()..add(beef, beef.variants[0]);
      await open(tester);
      server.prices[2003] = 7000;
      server.orderAnswers.add(
        (_) => FakeOrderServer.json(409, {
          'error': 'quote_changed',
          'problems': [
            {
              'variantId': 2003,
              'kind': 'price_changed',
              'message': 'The price of Australian Beef Cubes changed from '
                  'AED 62.50 to AED 70.00.',
            },
          ],
        }),
      );
      await placeOrder(tester);
      expect(
        find.textContaining(
          'The price of Australian Beef Cubes changed from AED 62.50 to '
          'AED 70.00.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('now costs'), findsNothing);
      // The new quote: 70.00 + 25.00; the cart follows the store.
      expect(find.text('Place order · ⃃ 95.00'), findsOneWidget);
      expect(cart.lineOf(2003)!.priceCents, 7000);
    });

    testWidgets('"Your order changed" is said once (announced, not also a '
        'live region)', (tester) async {
      server.stock[2001] = 1;
      final handle = tester.ensureSemantics();
      await open(tester);
      final node = tester.getSemantics(
        find.descendant(
          of: find.byKey(const ValueKey('checkout-changed')),
          matching: find.byType(Semantics),
        ).first,
      );
      expect(node.flagsCollection.isLiveRegion, isFalse);
      handle.dispose();
    });
  });
}
