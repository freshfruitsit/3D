import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/models/order.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/my_orders_screen.dart';
import 'package:fresh_market_app/screens/order_placed_screen.dart';
import 'package:fresh_market_app/services/customer_account_api.dart';
import 'package:fresh_market_app/services/customer_auth.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/order_fakes.dart';
import 'support/test_app.dart';

void main() {
  group('status, as "My orders" says it', () {
    OrderStatus s({
      String? financial,
      String? fulfillment,
      String? state,
      String? shipment,
      bool cancelled = false,
    }) => OrderStatus.from(
      financialStatus: financial,
      fulfillmentStatus: fulfillment,
      fulfillmentState: state,
      latestShipmentStatus: shipment,
      isCancelled: cancelled,
    );

    test('Placed until it moves', () {
      expect(
        s(financial: 'PENDING', fulfillment: 'UNFULFILLED'),
        OrderStatus.placed,
      );
      expect(s(fulfillment: 'OPEN'), OrderStatus.placed);
      expect(s(fulfillment: 'ON_HOLD'), OrderStatus.placed);
      expect(s(fulfillment: 'SCHEDULED'), OrderStatus.placed);
      expect(s(), OrderStatus.placed);
    });

    test('On the way once it is being delivered', () {
      expect(
        s(financial: 'PENDING', fulfillment: 'FULFILLED'),
        OrderStatus.onTheWay,
      );
      expect(s(fulfillment: 'IN_PROGRESS'), OrderStatus.onTheWay);
      expect(s(fulfillment: 'PARTIALLY_FULFILLED'), OrderStatus.onTheWay);
      expect(s(state: 'SUCCESS'), OrderStatus.onTheWay);
      expect(s(shipment: 'OUT_FOR_DELIVERY'), OrderStatus.onTheWay);
      expect(s(shipment: 'IN_TRANSIT'), OrderStatus.onTheWay);
    });

    test('Delivered: the delivery event, or fulfilled and the cash taken', () {
      expect(s(shipment: 'DELIVERED'), OrderStatus.delivered);
      expect(
        s(financial: 'PAID', fulfillment: 'FULFILLED'),
        OrderStatus.delivered,
      );
    });

    test('Cancelled and Refunded come first', () {
      expect(
        s(cancelled: true, fulfillment: 'FULFILLED'),
        OrderStatus.cancelled,
      );
      expect(s(financial: 'VOIDED'), OrderStatus.cancelled);
      expect(
        s(financial: 'REFUNDED', shipment: 'DELIVERED'),
        OrderStatus.refunded,
      );
    });

    test('finished (Buy again) once delivered, cancelled or refunded', () {
      expect(
        [for (final st in OrderStatus.values) if (st.finished) st],
        [OrderStatus.delivered, OrderStatus.cancelled, OrderStatus.refunded],
      );
    });
  });

  group('an order from the Customer Account API', () {
    test('read in full; the summary line', () {
      final order = CustomerOrder.fromJson(
        orderJson(
          fulfillmentStatus: 'FULFILLED',
          fulfillments: [
            {'status': 'SUCCESS', 'latestShipmentStatus': 'OUT_FOR_DELIVERY'},
          ],
        ),
      );
      expect(order.name, '#1001');
      expect(order.totalFils, 14750);
      expect(order.status, OrderStatus.onTheWay);
      expect(order.itemCount, 3);
      expect(order.lines.first.variantId, 2001);
      expect(order.lines.first.imageUrl, 'https://cdn.example.com/kiwi.jpg');
      expect(order.lines.last.imageUrl, isNull);
      expect(order.paymentLabel, 'Cash on Delivery');
      final now = DateTime.utc(2026, 11, 13, 10);
      expect(
        MyOrdersScreen.summaryLine(order, now),
        'Today · 3 items · ⃃\u00A0147.50 · Cash on Delivery',
      );
    });

    test('dates in UAE time; paid orders say so', () {
      final now = DateTime.utc(2026, 11, 13, 10); // 2 PM in Dubai
      expect(
        MyOrdersScreen.dateLabel(DateTime.utc(2026, 11, 12, 21), now),
        'Today',
        reason: '1 AM on the 13th in Dubai',
      );
      expect(
        MyOrdersScreen.dateLabel(DateTime.utc(2026, 11, 12, 10), now),
        'Yesterday',
      );
      expect(
        MyOrdersScreen.dateLabel(DateTime.utc(2026, 11, 1, 10), now),
        '1 Nov',
      );
      expect(
        MyOrdersScreen.dateLabel(DateTime.utc(2025, 12, 30, 10), now),
        '30 Dec 2025',
      );
      final paid = CustomerOrder.fromJson(orderJson(financialStatus: 'PAID'));
      expect(paid.paymentLabel, 'Paid');
      final refunded = CustomerOrder.fromJson(
        orderJson(financialStatus: 'REFUNDED'),
      );
      expect(refunded.paymentLabel, isNull);
    });

    test('a broken order is refused, not shown half', () {
      expect(
        () => CustomerOrder.fromJson({'id': 'x', 'name': '#1'}),
        throwsFormatException,
      );
    });
  });

  group('CustomerAccountApi', () {
    test('the raw token (no "Bearer") and the checked query', () async {
      late http.Request sent;
      final api = CustomerAccountApi(
        client: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'data': {
                'customer': {
                  'orders': {
                    'nodes': [orderJson()],
                  },
                },
              },
            }),
            200,
          );
        }),
      );
      final orders = await api.orders('shcat_token');
      expect(orders.single.name, '#1001');
      expect(
        sent.url.toString(),
        'https://shopify.com/79173124173/account/customer/api/2026-10/graphql',
      );
      expect(sent.headers['authorization'], 'shcat_token');
      final query = (jsonDecode(sent.body) as Map)['query'] as String;
      for (final field in [
        'orders(first: 20, sortKey: PROCESSED_AT, reverse: true)',
        'processedAt',
        'totalPrice { amount currencyCode }',
        'financialStatus',
        'fulfillmentStatus',
        'fulfillments(first: 1, sortKey: CREATED_AT, reverse: true)',
        'latestShipmentStatus',
        'lineItems(first: 20)',
        'nodes { title name quantity image { url } variantId }',
      ]) {
        expect(query, contains(field));
      }
    });

    test('ACCESS_DENIED is an error to try again, not "sign in again" '
        '(only a 401 or UNAUTHENTICATED is)', () async {
      final fake = FakeCustomerApi()..errorCode = 'ACCESS_DENIED';
      await expectLater(
        fake.api().orders('t'),
        throwsA(isA<CustomerApiError>()),
      );
      fake.errorCode = 'UNAUTHENTICATED';
      await expectLater(
        fake.api().orders('t'),
        throwsA(isA<CustomerApiUnauthorized>()),
      );
    });

    testWidgets('My orders: ACCESS_DENIED shows the error with Try again, '
        'not the sign-in page, and nothing is refreshed', (tester) async {
      final fake = FakeCustomerApi()..errorCode = 'ACCESS_DENIED';
      final oauth = FakeOAuthClient();
      await pumpScreen(
        tester,
        const MyOrdersScreen(),
        session: await signedInSession(client: oauth),
        customerApi: fake.api(),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('orders-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('orders-signed-out')), findsNothing);
      expect(oauth.refreshCalls, 0);
    });

    test('the customer; 401, GraphQL errors and the network', () async {
      final fake = FakeCustomerApi();
      final profile = await fake.api().customer('t');
      expect(profile.email, 'sara@example.com');
      expect(profile.phone, '+971501234567');
      expect(profile.firstName, 'Sara');

      fake.rejected.add('bad');
      expect(fake.api().orders('bad'), throwsA(isA<CustomerApiUnauthorized>()));
      fake.errorCode = 'THROTTLED';
      expect(fake.api().orders('t'), throwsA(isA<CustomerApiError>()));
      fake
        ..errorCode = null
        ..status = 500;
      expect(fake.api().orders('t'), throwsA(isA<CustomerApiError>()));
      final offline = CustomerAccountApi(
        client: MockClient((_) async => throw http.ClientException('off')),
      );
      expect(offline.orders('t'), throwsA(isA<CustomerApiNetworkError>()));
    });
  });

  group('MyOrdersScreen', () {
    late FakeCustomerApi customer;
    late FakeOAuthClient oauth;

    setUp(() {
      customer = FakeCustomerApi(
        orders: [
          orderJson(
            fulfillmentStatus: 'FULFILLED',
            fulfillments: [
              {'status': 'SUCCESS', 'latestShipmentStatus': 'IN_TRANSIT'},
            ],
          ),
          orderJson(
            name: '#1000',
            processedAt: '2026-11-12T08:00:00Z',
            amount: '96.00',
            financialStatus: 'PAID',
            fulfillmentStatus: 'FULFILLED',
            lines: [
              {
                'title': 'Strawberry',
                'quantity': 1,
                'image': {'url': 'https://cdn.example.com/s.jpg'},
                'variantId': 'gid://shopify/ProductVariant/2008',
              },
              {
                'title': 'Cucumber',
                'quantity': 3,
                'image': {'url': 'https://cdn.example.com/c.jpg'},
                'variantId': 'gid://shopify/ProductVariant/2004',
              },
            ],
          ),
        ],
      );
      oauth = FakeOAuthClient();
    });

    Future<CartStore> open(WidgetTester tester, {bool settle = true}) async {
      final cart = CartStore();
      await pumpScreen(
        tester,
        const MyOrdersScreen(),
        cart: cart,
        delivery: testDelivery(at: DateTime.utc(2026, 11, 13, 10)),
        session: await signedInSession(client: oauth),
        customerApi: customer.api(),
      );
      if (settle) await tester.pumpAndSettle();
      return cart;
    }

    testWidgets('cards: number, status, date · items · total · payment, '
        'photos; Buy again once the order is finished', (tester) async {
      await open(tester);
      expect(find.text('My orders'), findsOneWidget);
      expect(customer.tokens.single, 'access-1');
      expect(find.text('#1001'), findsOneWidget);
      expect(find.text('On the way'), findsOneWidget);
      expect(
        find.text('Today · 3 items · ⃃\u00A0147.50 · Cash on Delivery'),
        findsOneWidget,
      );
      expect(find.text('#1000'), findsOneWidget);
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text('Yesterday · 4 items · ⃃\u00A096.00 · Paid'), findsOneWidget);
      // Only on the delivered order (as in the approved design), not on
      // the one still on its way.
      expect(find.text(MyOrdersScreen.buyAgain), findsOneWidget);
      expect(find.byKey(const ValueKey('buy-again-#1001')), findsNothing);
      // "On the way" is the green delivery highlight; Buy again is ink.
      final pill = tester.widget<Text>(find.text('On the way'));
      expect(pill.style!.color, AppColors.green);
      final buy = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('buy-again-#1000')),
      );
      expect(
        buy.style!.side!.resolve(const <WidgetState>{})!.color,
        AppColors.ink,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('buy-again-#1000'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('loading, then empty with Start shopping', (tester) async {
      customer
        ..orders = []
        ..hold = Completer<void>();
      await open(tester, settle: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('orders-loading')), findsOneWidget);
      customer.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text(MyOrdersScreen.emptyTitle), findsOneWidget);
      expect(find.text('Start shopping'), findsOneWidget);
    });

    testWidgets('an error says so; Try again loads', (tester) async {
      customer.status = 500;
      await open(tester);
      expect(find.byKey(const ValueKey('orders-error')), findsOneWidget);
      expect(
        find.text(
          "We couldn't load your orders just now. Try again in "
          'a moment.',
        ),
        findsOneWidget,
      );
      customer.status = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('#1001'), findsOneWidget);
    });

    testWidgets('401: a fresh token once; refused: sign in again', (
      tester,
    ) async {
      customer.rejected.add('access-1');
      await open(tester);
      expect(oauth.refreshCalls, 1);
      expect(customer.tokens, ['access-1', 'refreshed-1']);
      expect(find.text('#1001'), findsOneWidget);
    });

    testWidgets('the session ended: "Sign in to see your orders"', (
      tester,
    ) async {
      customer.rejected.add('access-1');
      oauth.refreshError = const RefreshRejected();
      await open(tester);
      expect(find.byKey(const ValueKey('orders-signed-out')), findsOneWidget);
      customer.rejected.clear();
      oauth.refreshError = null;
      await tester.tap(find.text('Sign in with email'));
      await tester.pumpAndSettle();
      expect(oauth.authorizeCalls, 1);
      expect(find.text('#1001'), findsOneWidget);
    });

    testWidgets('Buy again adds what the store still has, as many as '
        'ordered, and says what it could not', (tester) async {
      // #1001 delivered too (cash taken).
      customer.orders[0] = orderJson(
        financialStatus: 'PAID',
        fulfillmentStatus: 'FULFILLED',
      );
      final cart = await open(tester);
      await tester.tap(find.byKey(const ValueKey('buy-again-#1001')));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(2001), 2);
      expect(cart.quantityOf(2003), 1);
      expect(find.text('Added 3 items to your cart.'), findsOneWidget);
      expect(find.text('View cart'), findsOneWidget);

      // Strawberry 250 g is sold out; cucumbers are there.
      await tester.tap(find.byKey(const ValueKey('buy-again-#1000')));
      await tester.pumpAndSettle();
      expect(cart.quantityOf(2008), 0);
      expect(cart.quantityOf(2004), 3);
      expect(
        find.text(
          "Added 3 items to your cart. 1 item isn't available right now.",
        ),
        findsOneWidget,
      );
    });

    test('Buy again: an empty title (a product line) is looked up by its '
        'name, with or without the variant ending', () async {
      const line = OrderLine(
        title: '',
        name: 'Cucumber - 1 KG',
        quantity: 1,
        variantId: 2005,
      );
      expect(line.searchTerms, ['Cucumber - 1 KG', 'Cucumber']);
      final hit = await MyOrdersScreen.findVariant(
        FakeShopifyApi.sample(),
        line,
      );
      expect(hit, isNotNull);
      expect(hit!.$2.id, 2005);
      expect(
        const OrderLine(title: 'Kiwi', name: 'Kiwi', quantity: 1).searchTerms,
        ['Kiwi'],
      );
    });

    test('Buy again finds a variant through the store search', () async {
      final api = FakeShopifyApi.sample();
      final hit = await MyOrdersScreen.findVariant(
        api,
        const OrderLine(title: 'Cucumber', quantity: 1, variantId: 2005),
      );
      expect(hit!.$1.title, 'Cucumber');
      expect(hit.$2.id, 2005);
      expect(
        await MyOrdersScreen.findVariant(
          api,
          const OrderLine(title: 'Cucumber', quantity: 1, variantId: 999),
        ),
        isNull,
      );
      expect(
        await MyOrdersScreen.findVariant(
          api,
          const OrderLine(title: 'Cucumber', quantity: 1),
        ),
        isNull,
      );
    });
  });

  group('My orders sits in the Account tab', () {
    Future<ShellController> app(WidgetTester tester) async {
      usePhoneSize(tester);
      SharedPreferences.setMockInitialValues({});
      final shell = ShellController();
      await tester.pumpWidget(
        FreshMarketApp(
          api: FakeShopifyApi.sample(),
          cart: CartStore(),
          favourites: FavouritesStore(),
          deliveryStore: testDelivery(),
          locationServices: testLocationServices(),
          session: await signedInSession(),
          customerApi: FakeCustomerApi(orders: [orderJson()]).api(),
          shell: shell,
          showIntro: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return shell;
    }

    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('from Account: with the bottom bar; back goes to Account', (
      tester,
    ) async {
      final shell = await app(tester);
      shell.select(AppTab.account);
      await frames(tester);
      await tester.tap(find.byKey(const ValueKey('account-orders')));
      await frames(tester);
      expect(find.byType(MyOrdersScreen), findsOneWidget);
      expect(find.text('#1001'), findsOneWidget);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      expect(shell.tab, AppTab.account);
      await tester.tap(find.byTooltip('Back'));
      await frames(tester);
      expect(find.byType(MyOrdersScreen), findsNothing);
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    testWidgets('from Order placed: it closes, Account shows My orders with '
        'the bar', (tester) async {
      final shell = await app(tester);
      final root = Navigator.of(
        tester.element(find.byType(AppShell)),
        rootNavigator: true,
      );
      unawaited(
        root.push(
          MaterialPageRoute<void>(
            builder: (_) => const OrderPlacedScreen(
              order: PlacedOrder(
                orderId: 'gid://shopify/Order/1001',
                orderName: '#1001',
                totalFils: 14750,
                deliveryPromise: 'Today within 6 hours',
              ),
              deliveryPromise: 'Today within 6 hours',
              addressLine: 'Home · Bay Square, Building 5 · Flat 302',
            ),
          ),
        ),
      );
      await frames(tester);
      // Order placed covers the bar.
      expect(find.byType(FloatingNavBar), findsNothing);
      expect(find.byType(OrderPlacedScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-placed-view-orders')));
      await frames(tester);
      expect(
        find.byType(OrderPlacedScreen, skipOffstage: false),
        findsNothing,
      );
      expect(shell.tab, AppTab.account);
      expect(find.byType(MyOrdersScreen), findsOneWidget);
      expect(find.byType(FloatingNavBar), findsOneWidget);
    });
  });
}
