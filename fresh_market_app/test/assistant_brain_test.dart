import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';

Product plain(int id, String title) => Product(
      id: id,
      title: title,
      handle: 'p$id',
      variants: [Variant(id: id + 5000, title: 'Default Title', priceCents: 500)],
    );

void main() {
  late FakeShopifyApi api;
  late CartStore cart;
  late AssistantBrain brain;

  setUp(() {
    api = FakeShopifyApi.sample();
    cart = CartStore();
    brain = AssistantBrain(api: api, cart: cart);
  });

  group('add', () {
    test('adds the first available variant with the quantity', () async {
      final reply = await brain.reply('Add 2 cucumbers');

      expect(reply.text, 'Done. I added 2 × Cucumber (500 GM) to your cart.');
      expect(reply.products.single.title, 'Cucumber');
      expect(reply.actions.single, isA<OpenCartAction>());
      expect(reply.actions.single.label, 'Open cart');
      expect(cart.quantityOf(2004), 2);
      // As typed first, then singular.
      expect(api.calls, ['search(cucumbers)', 'search(cucumber)']);
    });

    test('skips a sold-out weight and a product without options has no '
        'brackets', () async {
      var reply = await brain.reply('buy strawberry');
      expect(reply.text, 'Done. I added 1 × Strawberry (1 KG) to your cart.');
      expect(cart.quantityOf(2009), 1);

      reply = await brain.reply('add three beef');
      expect(reply.text,
          'Done. I added 3 × Australian Beef Cubes to your cart.');
      expect(cart.quantityOf(2003), 3);
    });

    test('a sold-out product is not added', () async {
      final reply = await brain.reply('add blueberry');
      expect(reply.text, contains('Blueberry is sold out'));
      expect(reply.actions, isEmpty);
      expect(cart.isEmpty, isTrue);
    });

    test('nothing found', () async {
      final reply = await brain.reply('add 2 dragonfruit');
      expect(reply.text, contains('could not find "dragonfruit"'));
      expect(reply.text, contains('Add 2 cucumbers'));
      expect(reply.products, isEmpty);
      expect(cart.isEmpty, isTrue);
    });

    test('no product named asks for one without calling the store',
        () async {
      final reply = await brain.reply('add');
      expect(reply.text, contains('Tell me what to add'));
      expect(api.calls, isEmpty);
    });

    test('says how many were really added at the cart limit', () async {
      final cucumber = sampleProducts()[2];
      cart.add(cucumber, cucumber.variants.first, quantity: 95);
      var reply = await brain.reply('add 10 cucumber');
      expect(reply.text, startsWith('Done. I added 4 × Cucumber (500 GM)'));

      reply = await brain.reply('add 1 cucumber');
      expect(reply.text, contains('already holds the most'));
      expect(cart.quantityOf(2004), 99);
    });
  });

  group('review fixes', () {
    test('a question or a negation never adds', () async {
      for (final text in [
        'Where can I buy strawberries?',
        "Don't add cucumber",
        'I want to buy some cucumber',
        'Buy 1 get 1 free offers',
      ]) {
        await brain.reply(text);
        expect(cart.isEmpty, isTrue, reason: text);
      }
    });

    test('a weight shows the product instead of adding', () async {
      final reply = await brain.reply('add 2kg cucumber');
      expect(reply.text, contains('whole packs'));
      expect(reply.text, contains('nothing was added'));
      expect(reply.products.single.title, 'Cucumber');
      expect(cart.isEmpty, isTrue);
    });

    test('says when only the first of two items was added', () async {
      final reply = await brain.reply('Add 2 cucumber and 3 kiwi');
      expect(reply.text, startsWith('Done. I added 2 × Cucumber (500 GM)'));
      expect(reply.text, contains('one product per message'));
      expect(cart.itemCount, 2);
    });

    test('remove is refused with a way to the cart', () async {
      final kiwi = sampleProducts().first;
      cart.add(kiwi, kiwi.variants.first);
      final reply = await brain.reply('Remove kiwi from my cart');
      expect(reply.text, contains('cannot remove items yet'));
      expect(reply.actions.single, isA<OpenCartAction>());
      expect(cart.itemCount, 1);
      expect(api.calls, isEmpty);
    });

    test('searches ask the store for few products', () async {
      final limits = _LimitApi();
      final b = AssistantBrain(api: limits, cart: cart);
      await b.reply('Find kiwi');
      await b.reply('add kiwi');
      expect(limits.limits, [AssistantBrain.maxProducts, 4]);
    });

    test('a 429 is retried once', () async {
      final busy = _BusyApi(failures: 1);
      var reply = await AssistantBrain(
        api: busy,
        cart: cart,
        retryDelay: Duration.zero,
      ).reply('Find kiwi');
      expect(reply.products, isNotEmpty);
      expect(busy.searches, 2);

      final down = _BusyApi(failures: 5);
      reply = await AssistantBrain(
        api: down,
        cart: cart,
        retryDelay: Duration.zero,
      ).reply('Find kiwi');
      expect(reply.products, isEmpty);
      expect(down.searches, 2);
    });
  });

  test('checkout', () async {
    var reply = await brain.reply('checkout');
    expect(reply.text, contains('Your cart is empty'));
    expect(reply.actions, isEmpty);

    final kiwi = sampleProducts().first;
    cart.add(kiwi, kiwi.variants.first, quantity: 2);
    reply = await brain.reply('I want to pay');
    expect(reply.actions.map((a) => a.label),
        ['Go to checkout', 'Review cart']);
    expect(reply.actions.first, isA<CheckoutAction>());
    expect(reply.actions.last, isA<OpenCartAction>());
    expect(api.calls, isEmpty);
  });

  test('cart', () async {
    var reply = await brain.reply('Open my cart');
    expect(reply.text, 'Your cart is empty.');
    expect(reply.actions.single.label, 'Open cart');

    final kiwi = sampleProducts().first;
    cart.add(kiwi, kiwi.variants.first);
    reply = await brain.reply('basket');
    expect(reply.text, 'Your cart has 1 item, subtotal Dhs. 19.95.');

    cart.add(kiwi, kiwi.variants.last, quantity: 2);
    reply = await brain.reply('cart');
    expect(reply.text, 'Your cart has 3 items, subtotal Dhs. 99.45.');
    expect(reply.actions.single, isA<OpenCartAction>());
  });

  group('offers', () {
    test('shows products really on sale, biggest saving first', () async {
      final reply = await brain.reply('What is on offer?');

      expect(api.calls, [
        'collectionProducts(fresh-meat, page 1)',
        'collectionProducts(best-deals, page 1)',
      ]);
      // The sample has two products on sale; each appears once.
      expect(reply.products.map((p) => p.title),
          ['Australian Beef Cubes', 'Strawberry']);
      expect(reply.text,
          'These are on sale today. The biggest saving is 46% on '
          'Australian Beef Cubes.');
      final action = reply.actions.single as OpenCollectionAction;
      // The collection the rows came from, not always best-deals.
      expect(action.label, "See all Today's Top Deals");
      expect(action.handle, 'fresh-meat');
      expect(action.title, "Today's Top Deals");
    });

    test('at most three', () async {
      Product sale(int id, int old) => Product(
            id: id,
            title: 'Sale $id',
            handle: 's$id',
            variants: [
              Variant(
                id: id + 100,
                title: 'Default Title',
                priceCents: 1000,
                compareAtCents: old,
              ),
            ],
          );
      api = FakeShopifyApi(collections: {
        'fresh-meat': [sale(1, 1100), sale(2, 2000)],
        'best-deals': [sale(3, 1250), sale(4, 4000), plain(5, 'Plain')],
      });
      final reply =
          await AssistantBrain(api: api, cart: cart).reply('deals');
      expect(reply.products.map((p) => p.id), [4, 2, 3]);
      expect(reply.text, contains('75% on Sale 4'));
      // One button per collection shown, the best saving's first.
      expect(
        reply.actions.map((a) => (a as OpenCollectionAction).handle),
        ['best-deals', 'fresh-meat'],
      );
      expect(reply.actions.first.label, 'See all Best Deals');
    });

    test('nothing on sale: the first three of best-deals, no discount '
        'claimed', () async {
      api = FakeShopifyApi(collections: {
        'fresh-meat': [plain(1, 'Lamb')],
        'best-deals': [
          plain(2, 'A'),
          plain(3, 'B'),
          plain(4, 'C'),
          plain(5, 'D'),
        ],
      });
      final reply =
          await AssistantBrain(api: api, cart: cart).reply('any discounts?');
      expect(reply.products.map((p) => p.title), ['A', 'B', 'C']);
      expect(reply.text, isNot(contains('%')));
      expect(reply.text, contains('Nothing is marked down'));
      expect(reply.actions.single.label, 'See all deals');
    });

    test('one collection missing still answers from the other', () async {
      api = FakeShopifyApi(collections: {'best-deals': sampleProducts()});
      final reply = await AssistantBrain(api: api, cart: cart).reply('sale');
      expect(reply.products, isNotEmpty);
    });
  });

  group('category', () {
    test('first three products and an Open action', () async {
      final reply = await brain.reply('Show me berries');
      expect(reply.text, 'Here is Berries.');
      expect(reply.products.map((p) => p.title),
          ['Zespri Kiwi Sungold', 'Australian Beef Cubes', 'Cucumber']);
      final action = reply.actions.single as OpenCollectionAction;
      expect(action.label, 'Open Berries');
      expect(action.handle, 'berries');
      expect(action.title, 'Berries');
    });

    test('an alias uses the tile title and handle', () async {
      final reply = await brain.reply('butchery');
      expect(reply.text, 'Here is Meat.');
      expect((reply.actions.single as OpenCollectionAction).handle,
          'fresh-meat');
    });

    test('a collection the store does not have', () async {
      final reply = await brain.reply('hampers');
      expect(reply.text, 'I could not find Hampers in the store right now.');
      expect(reply.products, isEmpty);
    });

    test('an empty collection', () async {
      api = FakeShopifyApi(collections: {'fresh-herbs': []});
      final reply = await AssistantBrain(api: api, cart: cart).reply('herbs');
      expect(reply.text, 'Herbs has no products in the store right now.');
    });
  });

  group('search', () {
    test('up to three results and See all results', () async {
      api = FakeShopifyApi(collections: {
        'fruits': [for (var i = 1; i <= 5; i++) plain(i, 'Apple $i')],
      });
      final reply =
          await AssistantBrain(api: api, cart: cart).reply('find apple');
      expect(reply.products.map((p) => p.title),
          ['Apple 1', 'Apple 2', 'Apple 3']);
      final action = reply.actions.single as OpenSearchAction;
      expect(action.label, 'See all results');
      expect(action.query, 'apple');
    });

    test('no results gives things to try', () async {
      final reply = await brain.reply('Find avocado');
      expect(reply.text, contains('could not find anything for "avocado"'));
      expect(reply.text, contains('Show me berries'));
      expect(reply.products, isEmpty);
      expect(reply.actions, isEmpty);
    });

    test('nothing to search for does not call the store', () async {
      final reply = await brain.reply('hello');
      expect(reply.text, contains('Tell me a product or a category'));
      expect(api.calls, isEmpty);
    });
  });

  test('network errors', () async {
    api.error = const NetworkException('offline');
    for (final text in [
      'Add 2 cucumbers',
      'What is on offer?',
      'Show me berries',
      'Find avocado',
    ]) {
      final reply = await brain.reply(text);
      expect(reply.text, AssistantBrain.networkError, reason: text);
      expect(reply.products, isEmpty);
    }
    expect(AssistantBrain.networkError,
        'I could not reach the store. Check your connection and try again.');
    expect(cart.isEmpty, isTrue);
  });

  test('other store errors use the store message', () async {
    api.error = const HttpStatusException(500, 'boom');
    final reply = await brain.reply('find kiwi');
    expect(reply.text,
        'The store is not responding right now. Please try again.');
  });
}

class _LimitApi extends FakeShopifyApi {
  _LimitApi() : super(collections: {'fruits': sampleProducts()});

  final List<int> limits = [];

  @override
  Future<List<Product>> search(String query, {int limit = 10}) {
    limits.add(limit);
    return super.search(query, limit: limit);
  }
}

/// Answers 429 to the first [failures] searches.
class _BusyApi extends FakeShopifyApi {
  _BusyApi({required this.failures})
      : super(collections: {'fruits': sampleProducts()});

  final int failures;
  int searches = 0;

  @override
  Future<List<Product>> search(String query, {int limit = 10}) async {
    if (searches++ < failures) {
      throw const HttpStatusException(429, 'HTTP 429');
    }
    return super.search(query, limit: limit);
  }
}
