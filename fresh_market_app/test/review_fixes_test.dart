import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

Product withPrice(Product p, int cents, {bool available = true}) => Product(
      id: p.id,
      title: p.title,
      handle: p.handle,
      vendor: p.vendor,
      tags: p.tags,
      images: p.images,
      options: p.options,
      variants: [
        for (final v in p.variants)
          Variant(
            id: v.id,
            title: v.title,
            priceCents: cents,
            available: available,
          ),
      ],
    );

void main() {
  final products = sampleProducts();
  final kiwi = products[0];
  final beef = products[1];
  final bouquet = products[4];

  group('order confirmation URL', () {
    test('matches thank-you and order status pages of the store', () {
      const yes = [
        'https://testtfm.myshopify.com/checkouts/cn/abc123/en-ae/thank-you',
        'https://testtfm.myshopify.com/checkouts/cn/abc123/thank_you?x=1',
        'https://testtfm.myshopify.com/61234/orders/0a1b2c3d',
        'https://checkout.shopify.com/61234/checkouts/abc/thank_you',
      ];
      const no = [
        'https://testtfm.myshopify.com/cart/2001:1',
        'https://testtfm.myshopify.com/checkouts/cn/abc123/en-ae',
        'https://testtfm.myshopify.com/account/orders/123',
        'https://testtfm.myshopify.com/orders/',
        'https://bank.example.com/3ds/orders/123',
        'not a url %%',
      ];
      for (final url in yes) {
        expect(isOrderConfirmationUrl(url), isTrue, reason: url);
      }
      for (final url in no) {
        expect(isOrderConfirmationUrl(url), isFalse, reason: url);
      }
    });

    test('storefront links leave checkout, checkout links do not', () {
      const leaves = [
        'https://testtfm.myshopify.com',
        'https://testtfm.myshopify.com/',
        'https://testtfm.myshopify.com/cart',
        'https://testtfm.myshopify.com/collections/fruits',
        'https://testtfm.myshopify.com/products/cucumber',
      ];
      const stays = [
        'https://testtfm.myshopify.com/cart/2001:1,2003:2',
        'https://testtfm.myshopify.com/checkouts/cn/abc123',
        'https://testtfm.myshopify.com/account/login',
        'https://testtfm.myshopify.com/customer_authentication/login',
        'https://pay.example.com/',
      ];
      for (final url in leaves) {
        expect(leavesCheckoutUrl(url), isTrue, reason: url);
      }
      for (final url in stays) {
        expect(leavesCheckoutUrl(url), isFalse, reason: url);
      }
    });
  });

  group('CartStore.revalidate', () {
    test('drops lines the store no longer has and refreshes prices',
        () async {
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0])
        ..add(bouquet, bouquet.variants[0]);
      // The store now: kiwi cheaper, beef with other variants, no bouquet.
      final api = FakeShopifyApi(collections: {
        'all': [
          withPrice(kiwi, 1500),
          Product(
            id: beef.id,
            title: beef.title,
            handle: beef.handle,
            variants: const [
              Variant(id: 9999, title: '1 KG', priceCents: 100),
            ],
          ),
        ],
      });
      var notified = 0;
      cart.addListener(() => notified++);

      expect(await cart.revalidate(api), 2);
      expect(notified, 1);
      final line = cart.lines.single;
      expect(line.variantId, kiwi.variants[0].id);
      expect(line.quantity, 2);
      expect(line.priceCents, 1500);
      expect(cart.subtotalCents, 3000);

      // Nothing left to change: no second notification.
      expect(await cart.revalidate(api), 0);
      expect(notified, 1);
    });

    test('keeps the cart when the store cannot be reached', () async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      final api = FakeShopifyApi()..error = const NetworkException('offline');
      expect(await cart.revalidate(api), 0);
      expect(cart.itemCount, 1);
    });

    testWidgets('the cart tells the shopper and Checkout stays on the cart',
        (tester) async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      final api = FakeShopifyApi.sample();
      await pumpScreen(tester, const CartScreen(),
          cart: cart, api: api, delivery: testDelivery());
      await tester.pumpAndSettle();
      expect(cart.itemCount, 1);

      // The product disappears from the store before checkout.
      api.collectionsByHandle.clear();
      await tester.tap(find.ancestor(of: find.textContaining('Checkout · '), matching: find.byType(FilledButton)));
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsNothing);
      expect(cart.isEmpty, isTrue);
      expect(
        find.text('Some items are no longer available and were removed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a cart row that cannot be opened says why', (tester) async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      final api = FakeShopifyApi.sample();
      await pumpScreen(tester, const CartScreen(), cart: cart, api: api);
      await tester.pumpAndSettle();

      api
        ..error = const NetworkException('offline')
        ..delay = const Duration(milliseconds: 200);
      await tester.tap(find.text(kiwi.title));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(find.textContaining('could not reach the store'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('FavouritesStore.refresh', () {
    test('updates prices, keeps order, marks deleted products sold out',
        () async {
      final favourites = FavouritesStore()
        ..toggle(kiwi)
        ..toggle(beef);
      final api = FakeShopifyApi(collections: {
        'all': [withPrice(kiwi, 1500)],
      });

      await favourites.refresh(api);

      expect(favourites.products.map((p) => p.id), [beef.id, kiwi.id]);
      expect(favourites.products[1].variants[0].priceCents, 1500);
      expect(favourites.products[0].available, isFalse);

      api.error = const NetworkException('offline');
      await favourites.refresh(api);
      expect(favourites.products[1].variants[0].priceCents, 1500);
    });

    testWidgets('the favourites list shows the refreshed stock',
        (tester) async {
      final favourites = FavouritesStore()..toggle(kiwi);
      final api = FakeShopifyApi(collections: {
        'all': [withPrice(kiwi, 1500, available: false)],
      });
      await pumpScreen(
        tester,
        const ProductListScreen.favourites(),
        favourites: favourites,
        api: api,
      );
      await tester.pumpAndSettle();
      expect(find.text('Sold out'), findsOneWidget);
      expect(find.text('\u20C3 15.00'), findsOneWidget);
    });
  });

  group('HttpShopifyApi product cache', () {
    test('expires after five minutes and refresh skips it', () async {
      var requests = 0;
      final body = File('test/fixtures/product_js.json').readAsStringSync();
      final api = HttpShopifyApi(client: MockClient((request) async {
        requests++;
        return http.Response.bytes(utf8.encode(body), 200);
      }));
      var clock = DateTime(2026, 1, 1, 12);
      api.now = () => clock;

      await api.product('x');
      await api.product('x');
      expect(requests, 1);

      await api.product('x', refresh: true);
      expect(requests, 2);

      clock = clock.add(const Duration(minutes: 6));
      await api.product('x');
      expect(requests, 3);
    });
  });

  group('brand search', () {
    testWidgets('keeps only products that name the brand', (tester) async {
      // The store matches descriptions too, like the fake below.
      final api = _LooseSearchApi(sampleProducts());
      await pumpScreen(
        tester,
        const SearchScreen(initialQuery: 'Zespri'),
        api: api,
      );
      await tester.pumpAndSettle();
      expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);
      expect(find.text('Cucumber'), findsNothing);
      expect(find.text('1 result'), findsOneWidget);
    });

    testWidgets('shows no results when nothing names the brand',
        (tester) async {
      final api = _LooseSearchApi(sampleProducts());
      await pumpScreen(
        tester,
        const SearchScreen(initialQuery: 'Juliet'),
        api: api,
      );
      await tester.pumpAndSettle();
      expect(find.text('No results for "Juliet"'), findsOneWidget);
    });
  });

  group('large system font', () {
    testWidgets('stepper with two digits fits a narrow box', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Center(
              child: SizedBox(
                width: 112,
                child: QuantityStepper(
                  quantity: 99,
                  onDecrement: () {},
                  onIncrement: () {},
                  expand: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Answers every search with all its products, however unrelated.
class _LooseSearchApi extends FakeShopifyApi {
  _LooseSearchApi(List<Product> products)
      : super(collections: {'all': products});

  @override
  Future<List<Product>> search(String query, {int limit = 10}) async =>
      collectionsByHandle['all']!;
}
