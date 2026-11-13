import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/assistant/assistant_intent.dart';
import 'package:fresh_market_app/data/catalog.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';

Product plain(int id, String title) => Product(
  id: id,
  title: title,
  handle: 'p$id',
  variants: [Variant(id: id + 5000, title: 'Default Title', priceCents: 500)],
);

/// One product with one variant at [cents].
Product priced(
  int id,
  String title,
  int cents, {
  bool available = true,
  String variant = 'Default Title',
}) => Product(
  id: id,
  title: title,
  handle: 'p$id',
  variants: [
    Variant(
      id: id + 5000,
      title: variant,
      priceCents: cents,
      available: available,
    ),
  ],
);

/// The sample products plus what the recipe and budget tests need.
/// Search matches title substrings, so "banana" also finds "Bananarama
/// Bread" (whose word is not "banana") and "blueberry" finds the sold-out
/// Blueberry first.
List<Product> shelf() => [
  ...sampleProducts(),
  priced(1, 'Bananarama Bread', 900),
  priced(2, 'Banana Chiquita', 650),
  priced(3, 'Organic Blueberry Punnet', 2400),
  priced(4, 'Mango Alphonso', 3000),
  priced(5, 'Avocado Hass', 1250),
  priced(6, 'Avocado Shepard', 800),
  priced(7, 'Avocado Organic', 2000),
  priced(8, 'Avocado Fuerte', 500, available: false),
  priced(9, 'Avocado Mini', 800),
  priced(10, 'Tomatoes Cherry', 450, variant: '250 GM'),
  priced(11, 'Red Onions', 300),
];

/// Chips with a fixed meaning and the intent each must parse to.
final Map<String, Matcher> fixedChips = {
  'What is on offer?': isA<OffersIntent>(),
  'What is popular?': isA<CollectionIntent>().having(
    (i) => i.collection.handle,
    'handle',
    'best-sellers',
  ),
  'Show all categories': isA<AllCategoriesIntent>(),
  'Open my cart': isA<CartIntent>(),
  'Checkout': isA<CheckoutIntent>(),
  'Empty my cart': isA<ClearCartIntent>(),
  'Show me berries': isA<CategoryIntent>(),
  'Add 2 cucumbers': isA<AddIntent>(),
  'Cheapest avocado': isA<CheapestIntent>(),
  'Delivery information': isA<DeliveryIntent>(),
  'Payment methods': isA<PaymentIntent>(),
  'Contact customer service': isA<ContactIntent>(),
  'Show 1Hr Express': isA<CollectionIntent>().having(
    (i) => i.collection.handle,
    'handle',
    'express',
  ),
  'Show local UAE produce': isA<CollectionIntent>().having(
    (i) => i.collection.handle,
    'handle',
    'local-uae',
  ),
  "What's new?": isA<CollectionIntent>()
      .having((i) => i.collection.handle, 'handle', 'new-arrivals'),
  'Recipe ideas': isA<RecipeIdeasIntent>(),
  'Gift ideas': isA<CategoryIntent>().having(
    (i) => i.category.handle,
    'handle',
    'hampers',
  ),
};

/// [chip] parses to the request it reads as, never to a search.
void expectChipParses(String chip) {
  final intent = AssistantIntentParser.parse(chip);
  expect(intent, isNot(isA<SearchIntent>()), reason: chip);
  final fixed = fixedChips[chip];
  if (fixed != null) {
    expect(intent, fixed, reason: chip);
  } else if (chip.startsWith('Add 1 ')) {
    expect(intent, isA<AddIntent>(), reason: chip);
    intent as AddIntent;
    expect(intent.quantity, 1, reason: chip);
    expect(intent.query, isNotEmpty, reason: chip);
    expect(intent.measureAsked || intent.moreItems, isFalse, reason: chip);
  } else if (chip.startsWith('Cheapest ')) {
    expect(intent, isA<CheapestIntent>(), reason: chip);
    expect((intent as CheapestIntent).query, isNotEmpty, reason: chip);
    expect(intent.maxPriceCents, isNull, reason: chip);
  } else if (chip.startsWith('Is ') && chip.endsWith(' in stock?')) {
    expect(intent, isA<StockIntent>(), reason: chip);
    expect((intent as StockIntent).query, isNotEmpty, reason: chip);
  } else if (chip.startsWith('How much is ')) {
    expect(intent, isA<PriceIntent>(), reason: chip);
    expect((intent as PriceIntent).query, isNotEmpty, reason: chip);
  } else if (chip.startsWith('Remove ')) {
    expect(intent, isA<RemoveIntent>(), reason: chip);
    expect((intent as RemoveIntent).query, isNotEmpty, reason: chip);
    expect(intent.quantity, isNull, reason: chip);
  } else if (chip.startsWith('Ideas for ')) {
    expect(intent, isA<RecipeIntent>(), reason: chip);
  } else {
    fail('A chip of unknown shape: "$chip"');
  }
}

/// 3 to 5 chips, each parsing to what it says.
void expectGoodChips(AssistantReply reply) {
  expect(reply.suggestions.length, inInclusiveRange(3, 5), reason: reply.text);
  expect(reply.suggestions.toSet(), hasLength(reply.suggestions.length));
  reply.suggestions.forEach(expectChipParses);
}

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
      expect(
        reply.text,
        'Done. I added 3 × Australian Beef Cubes to your cart.',
      );
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

    test('no product named asks for one without calling the store', () async {
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

    // Was refused ("cannot remove items yet"); remove works now.
    test('remove takes the line out without calling the store', () async {
      final kiwi = sampleProducts().first;
      cart.add(kiwi, kiwi.variants.first);
      final reply = await brain.reply('Remove kiwi from my cart');
      expect(
        reply.text,
        'Removed Zespri Kiwi Sungold (500 GM) from your cart. Your cart '
        'is empty now.',
      );
      expect(reply.actions.single, isA<OpenCartAction>());
      expect(cart.isEmpty, isTrue);
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
    expect(reply.actions.map((a) => a.label), [
      'Go to checkout',
      'Review cart',
    ]);
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
      expect(reply.products.map((p) => p.title), [
        'Australian Beef Cubes',
        'Strawberry',
      ]);
      expect(
        reply.text,
        'These are on sale today. The biggest saving is 46% on '
        'Australian Beef Cubes.',
      );
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
      api = FakeShopifyApi(
        collections: {
          'fresh-meat': [sale(1, 1100), sale(2, 2000)],
          'best-deals': [sale(3, 1250), sale(4, 4000), plain(5, 'Plain')],
        },
      );
      final reply = await AssistantBrain(api: api, cart: cart).reply('deals');
      expect(reply.products.map((p) => p.id), [4, 2, 3]);
      expect(reply.text, contains('75% on Sale 4'));
      // One button per collection shown, the best saving's first.
      expect(reply.actions.map((a) => (a as OpenCollectionAction).handle), [
        'best-deals',
        'fresh-meat',
      ]);
      expect(reply.actions.first.label, 'See all Best Deals');
    });

    test('nothing on sale: the first three of best-deals, no discount '
        'claimed', () async {
      api = FakeShopifyApi(
        collections: {
          'fresh-meat': [plain(1, 'Lamb')],
          'best-deals': [
            plain(2, 'A'),
            plain(3, 'B'),
            plain(4, 'C'),
            plain(5, 'D'),
          ],
        },
      );
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('any discounts?');
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
      expect(reply.text, 'A few products from Berries:');
      expect(reply.products.map((p) => p.title), [
        'Zespri Kiwi Sungold',
        'Australian Beef Cubes',
        'Cucumber',
      ]);
      final action = reply.actions.single as OpenCollectionAction;
      expect(action.label, 'Open Berries');
      expect(action.handle, 'berries');
      expect(action.title, 'Berries');
    });

    test('an alias uses the tile title and handle', () async {
      final reply = await brain.reply('butchery');
      expect(reply.text, 'A few products from Meat:');
      expect(
        (reply.actions.single as OpenCollectionAction).handle,
        'fresh-meat',
      );
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
      api = FakeShopifyApi(
        collections: {
          'fruits': [for (var i = 1; i <= 5; i++) plain(i, 'Apple $i')],
        },
      );
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('find apple');
      expect(reply.products.map((p) => p.title), [
        'Apple 1',
        'Apple 2',
        'Apple 3',
      ]);
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

    // "hello" was an empty search; it is a greeting now (see help).
    test('nothing to search for does not call the store', () async {
      final reply = await brain.reply('show me');
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
    expect(
      AssistantBrain.networkError,
      'I could not reach the store. Check your connection and try again.',
    );
    expect(cart.isEmpty, isTrue);
  });

  test('other store errors use the store message', () async {
    api.error = const HttpStatusException(500, 'boom');
    final reply = await brain.reply('find kiwi');
    expect(
      reply.text,
      'The store is not responding right now. Please try again.',
    );
  });

  group('help and small talk', () {
    test('help shows the options grid without calling the store', () async {
      for (final text in ['help', 'What can you do?', 'menu', 'options']) {
        final reply = await brain.reply(text);
        expect(reply.text, AssistantBrain.optionsReply.text, reason: text);
        expect(reply.showOptions, isTrue, reason: text);
      }
      final hello = await brain.reply('hello');
      expect(hello.text, startsWith('Hello!'));
      expect(hello.showOptions, isTrue);
      expect(api.calls, isEmpty);
    });

    test('thanks and bye', () async {
      var reply = await brain.reply('thank you so much');
      expect(
        reply.text,
        'You are welcome. Is there anything else I can help with?',
      );
      expectGoodChips(reply);

      reply = await brain.reply('bye');
      expect(
        reply.text,
        'Thank you for shopping with Fresh Market. Come back any time.',
      );
      expectGoodChips(reply);
      expect(api.calls, isEmpty);
    });
  });

  test('all categories: a button per tile and the Categories tab', () async {
    final reply = await brain.reply('Show all categories');
    expect(reply.text, 'Here are our categories.');
    expect(reply.products, isEmpty);
    final tiles = reply.actions.take(Catalog.categories.length).toList();
    expect(reply.actions, hasLength(Catalog.categories.length + 1));
    for (final (index, tile) in Catalog.categories.indexed) {
      final action = tiles[index] as OpenCollectionAction;
      expect(action.label, tile.label);
      expect(action.handle, tile.handle);
      expect(action.title, tile.label);
    }
    expect(reply.actions.last, isA<OpenCategoriesAction>());
    expectGoodChips(reply);
    expect(api.calls, isEmpty);
  });

  group('collections', () {
    test('a shortcut opens its collection like a category', () async {
      final reply = await brain.reply('Show local UAE produce');
      expect(reply.text, 'A few products from Local UAE:');
      expect(api.calls, ['collectionProducts(local-uae, page 1)']);
      expect(reply.products, hasLength(3));
      final action = reply.actions.single as OpenCollectionAction;
      expect(action.label, 'Open Local UAE');
      expect(action.handle, 'local-uae');
      expect(action.title, 'Local UAE');
      expectGoodChips(reply);
      // "Cheapest" needs a category word; a collection has none.
      expect(reply.suggestions.where((c) => c.startsWith('Cheapest')), isEmpty);
      expect(reply.suggestions, contains('Add 1 Zespri Kiwi Sungold'));
    });

    test('popular is Best Sellers', () async {
      final reply = await brain.reply('What is popular?');
      expect(reply.text, 'A few products from Best Sellers:');
      expect(
        (reply.actions.single as OpenCollectionAction).handle,
        'best-sellers',
      );
    });

    test('a collection the store does not have says so', () async {
      final reply = await brain.reply('fruit platter');
      expect(
        reply.text,
        'I could not find Fruit Platters in the store right now.',
      );
      expect(reply.products, isEmpty);
      expectGoodChips(reply);
    });

    test('a category offers its cheapest and its first product', () async {
      final reply = await brain.reply('Show me berries');
      expect(
        reply.suggestions,
        containsAll(['Cheapest berries', 'Add 1 Zespri Kiwi Sungold']),
      );
      expectGoodChips(reply);
    });

    test('gift ideas: Hampers plus flowers, bouquets and occasions', () async {
      api = FakeShopifyApi(collections: {'hampers': sampleProducts()});
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('Gift ideas');
      expect(reply.text, startsWith('A few gift ideas from Hampers.'));
      final actions = reply.actions.cast<OpenCollectionAction>();
      expect(actions.map((a) => a.label), [
        'Open Hampers',
        'Open Flowers',
        'Open Fruit Bouquets',
        'Open Special Occasions',
      ]);
      expect(actions.map((a) => a.handle), [
        'hampers',
        'ambrosia-flowers',
        'ambrosia-bouquets',
        'ambrosia-occasions',
      ]);
      expectGoodChips(reply);
    });
  });

  group('cheapest', () {
    late AssistantBrain shop;
    late _SearchLog log;
    setUp(() {
      log = _SearchLog({'fruits': shelf()});
      shop = AssistantBrain(api: log, cart: cart);
    });

    test('in stock only, lowest price first, equal prices keep the store '
        'order', () async {
      final reply = await shop.reply('Cheapest avocado');
      expect(reply.text, 'The cheapest avocado right now:');
      expect(reply.products.map((p) => p.title), [
        'Avocado Shepard',
        'Avocado Mini',
        'Avocado Hass',
      ]);
      final action = reply.actions.single as OpenSearchAction;
      expect(action.query, 'avocado');
      expect(log.limits, [20]);
      expectGoodChips(reply);
      expect(reply.suggestions, contains('Add 1 Avocado Shepard'));
    });

    test('a price limit keeps what costs at most that much', () async {
      var reply = await shop.reply('avocado under 10 dhs');
      expect(reply.text, 'Avocado under Dhs. 10.00:');
      expect(reply.products.map((p) => p.title), [
        'Avocado Shepard',
        'Avocado Mini',
      ]);

      reply = await shop.reply('avocado below AED 12.50');
      expect(reply.products.map((p) => p.title), [
        'Avocado Shepard',
        'Avocado Mini',
        'Avocado Hass',
      ]);
      expectGoodChips(reply);
    });

    test('nothing under the limit says so and shows the cheapest', () async {
      final reply = await shop.reply('avocado under 5');
      expect(
        reply.text,
        'Nothing for "avocado" is under Dhs. 5.00 right now. The cheapest '
        'is Avocado Shepard at Dhs. 8.00.',
      );
      expect(reply.products.single.title, 'Avocado Shepard');
      expectGoodChips(reply);
    });

    test('the price is the one the row shows (first size in stock)', () async {
      final reply = await shop.reply('cheapest strawberry under 30');
      // 250 GM (Dhs. 20.50) is sold out; the row shows 1 KG.
      expect(
        reply.text,
        'Nothing for "strawberry" is under Dhs. 30.00 right now. The '
        'cheapest is Strawberry (1 KG) at Dhs. 75.00.',
      );
    });

    test('everything sold out', () async {
      api = FakeShopifyApi(
        collections: {
          'fruits': [priced(1, 'Fig Black', 900, available: false)],
        },
      );
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('cheap figs');
      expect(
        reply.text,
        'Everything I found for "figs" is sold out right now.',
      );
      expect(reply.products.single.title, 'Fig Black');
      expectGoodChips(reply);
    });

    test('no product named asks without calling the store', () async {
      final reply = await shop.reply('cheapest');
      expect(reply.text, contains('Tell me what to look for'));
      expect(log.calls, isEmpty);
      expectGoodChips(reply);
    });

    test('related products the store suggests are not ranked', () async {
      // The live store's search for "avocado" also returns Guava, Plums
      // and Mango; the cheapest of those is not an avocado.
      final related = _FixedSearch([
        priced(21, 'Avocado Hass Periban', 2700),
        priced(22, 'Guava', 600),
        priced(23, 'Avocado Unripe', 1695),
        priced(24, 'Red Plums', 1195),
        Product(
          id: 25,
          title: 'Eat Me Ready To Eat',
          handle: 'p25',
          tags: const ['Avocados'],
          variants: const [
            Variant(id: 5025, title: 'Default Title', priceCents: 1795),
          ],
        ),
      ]);
      var reply = await AssistantBrain(
        api: related,
        cart: cart,
      ).reply('Cheapest avocado');
      expect(reply.text, 'The cheapest avocado right now:');
      expect(reply.products.map((p) => p.title), [
        'Avocado Unripe',
        'Eat Me Ready To Eat',
        'Avocado Hass Periban',
      ]);
      expectGoodChips(reply);

      // Nothing names the query: the store's results, said honestly.
      reply = await AssistantBrain(
        api: related,
        cart: cart,
      ).reply('Cheapest kiwano');
      expect(reply.text, 'The cheapest of what I found for "kiwano":');
      expect(reply.products.first.title, 'Guava');
      reply = await AssistantBrain(
        api: related,
        cart: cart,
      ).reply('kiwano under 15');
      expect(reply.text, 'What I found for "kiwano" under Dhs. 15.00:');
      expect(reply.products.map((p) => p.title), ['Guava', 'Red Plums']);
    });
  });

  group('price', () {
    test('first result with its size, other sizes and an old price', () async {
      var reply = await brain.reply('How much is kiwi?');
      expect(
        reply.text,
        'Zespri Kiwi Sungold (500 GM) is Dhs. 19.95. 1 KG is Dhs. 39.75.',
      );
      expect(reply.products.single.title, 'Zespri Kiwi Sungold');
      expect((reply.actions.single as OpenSearchAction).query, 'kiwi');
      expectGoodChips(reply);

      reply = await brain.reply('price of beef');
      expect(
        reply.text,
        'Australian Beef Cubes is Dhs. 62.50, down from Dhs. 115.00.',
      );

      reply = await brain.reply('how much is strawberry');
      expect(
        reply.text,
        'Strawberry (1 KG) is Dhs. 75.00, down from Dhs. 82.95.',
      );

      reply = await brain.reply('what does blueberry cost');
      expect(reply.text, 'Blueberry is Dhs. 31.25. It is sold out right now.');
      expectGoodChips(reply);
    });

    test('no product named or nothing found', () async {
      var reply = await brain.reply('how much');
      expect(reply.text, contains('Tell me which product'));
      expect(api.calls, isEmpty);

      reply = await brain.reply('how much is avocado');
      expect(reply.text, contains('could not find anything for "avocado"'));
      expectGoodChips(reply);
    });
  });

  group('stock', () {
    test('in stock, partly sold out, sold out', () async {
      var reply = await brain.reply('Is cucumber in stock?');
      expect(reply.text, 'Yes, Cucumber is in stock.');
      expect(reply.products.single.title, 'Cucumber');
      expectGoodChips(reply);

      reply = await brain.reply('is strawberry available');
      expect(
        reply.text,
        'Yes, Strawberry is in stock. 250 GM is sold out right now.',
      );

      reply = await brain.reply('is blueberry available?');
      expect(reply.text, 'Blueberry is sold out right now.');
      expectGoodChips(reply);
      expect(reply.suggestions.where((c) => c.startsWith('Add')), isEmpty);
    });

    test('a sold-out first result names one in stock', () async {
      api = FakeShopifyApi(
        collections: {
          'fruits': [
            priced(1, 'Blueberry', 3000, available: false),
            priced(2, 'Blueberry Jam', 1500),
          ],
        },
      );
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('do you have blueberry in stock');
      expect(
        reply.text,
        'Blueberry is sold out right now. Blueberry Jam is in stock.',
      );
      expect(reply.products, hasLength(2));
    });

    test('no product named asks', () async {
      final reply = await brain.reply('is it available?');
      expect(reply.text, contains('Tell me which product'));
      expect(api.calls, isEmpty);
    });
  });

  group('recipes', () {
    test('one product in stock per ingredient, and Add all to cart', () async {
      api = FakeShopifyApi(collections: {'fruits': shelf()});
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('Ideas for a fruit salad');
      expect(reply.text, 'For a fruit salad, you could use:');
      // Blueberry is sold out: the punnet is the first in stock. Bananarama
      // Bread contains "banana" but not as a word.
      final titles = [
        'Strawberry',
        'Zespri Kiwi Sungold',
        'Banana Chiquita',
        'Organic Blueberry Punnet',
      ];
      expect(reply.products.map((p) => p.title), titles);
      final addAll = reply.actions.first as AddProductsAction;
      expect(addAll.label, 'Add all to cart');
      expect(addAll.products.map((p) => p.title), titles);
      expect(addAll.products.every((p) => p.available), isTrue);
      final others = reply.actions.skip(1).cast<SendMessageAction>();
      expect(others.map((a) => a.label), [
        'Smoothie ideas',
        'Green salad ideas',
      ]);
      expect(others.map((a) => a.message), [
        'Ideas for a smoothie',
        'Ideas for a green salad',
      ]);
      // Nothing is added until the button is tapped.
      expect(cart.isEmpty, isTrue);
      expectGoodChips(reply);
      expect(reply.suggestions, contains('Ideas for guacamole'));
    });

    test('a plural title counts and a missing ingredient is named', () async {
      api = FakeShopifyApi(collections: {'fruits': shelf()});
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
      ).reply('how do I make guacamole');
      expect(
        reply.text,
        'For guacamole, you could use these. I could not find lime in '
        'stock right now.',
      );
      expect(reply.products.map((p) => p.title), [
        'Avocado Hass',
        'Tomatoes Cherry',
        'Red Onions',
      ]);
      expect((reply.actions.first as AddProductsAction).products, hasLength(3));
    });

    test('nothing in stock offers the other dishes', () async {
      final reply = await brain.reply('something for a bbq');
      expect(
        reply.text,
        'I could not find the ingredients for a BBQ in stock right now.',
      );
      expect(reply.products, isEmpty);
      expect(reply.actions.map((a) => a.label), [
        'Breakfast ideas',
        'Fruit salad ideas',
      ]);
      expectGoodChips(reply);
    });

    test('at most two searches at a time, four products at most', () async {
      final slow = _CountingApi({'fruits': shelf()});
      final reply = await AssistantBrain(
        api: slow,
        cart: cart,
      ).reply('smoothie recipe');
      expect(slow.maxInFlight, AssistantBrain.recipeSearchWidth);
      expect(AssistantBrain.recipeSearchWidth, 2);
      expect(slow.limits.toSet(), {4});
      expect(
        reply.products.length,
        lessThanOrEqualTo(AssistantBrain.maxRecipeProducts),
      );
      expect(reply.products.map((p) => p.title), [
        'Banana Chiquita',
        'Organic Blueberry Punnet',
        'Strawberry',
        'Mango Alphonso',
      ]);
    });

    test('a store failure is said plainly', () async {
      api.error = const NetworkException('offline');
      final reply = await brain.reply('Ideas for breakfast');
      expect(reply.text, AssistantBrain.networkError);
    });

    test('recipe ideas lists every dish as a button', () async {
      final reply = await brain.reply('recipe ideas');
      final buttons = reply.actions.cast<SendMessageAction>();
      expect(buttons.map((a) => a.label), [
        'Fruit salad ideas',
        'Smoothie ideas',
        'Green salad ideas',
        'Guacamole ideas',
        'BBQ ideas',
        'Breakfast ideas',
      ]);
      for (final button in buttons) {
        expect(
          AssistantIntentParser.parse(button.message),
          isA<RecipeIntent>(),
          reason: button.message,
        );
      }
      expectGoodChips(reply);
      expect(api.calls, isEmpty);
    });
  });

  group('remove', () {
    final kiwi = sampleProducts()[0];
    final cucumber = sampleProducts()[2];
    final strawberry = sampleProducts()[5];

    test('a number takes units off the line', () async {
      cart.add(cucumber, cucumber.variants.first, quantity: 3);
      cart.add(kiwi, kiwi.variants.first);
      var reply = await brain.reply('remove 1 cucumber');
      expect(
        reply.text,
        'Removed 1 × Cucumber (500 GM) from your cart. Your cart has 3 '
        'items, subtotal Dhs. 24.95.',
      );
      expect(cart.quantityOf(2004), 2);
      expect(reply.actions.single, isA<OpenCartAction>());
      expectGoodChips(reply);

      // More than the line holds removes the line.
      reply = await brain.reply('remove 5 cucumbers');
      expect(
        reply.text,
        'Removed 2 × Cucumber (500 GM) from your cart. Your cart has 1 '
        'item, subtotal Dhs. 19.95.',
      );
      expect(cart.quantityOf(2004), 0);
      expect(api.calls, isEmpty);
    });

    test('without a number every matching line goes', () async {
      cart.add(cucumber, cucumber.variants[0], quantity: 2);
      cart.add(cucumber, cucumber.variants[1]);
      cart.add(kiwi, kiwi.variants.first);
      final reply = await brain.reply('remove cucumbers');
      expect(
        reply.text,
        'Removed Cucumber (500 GM) and Cucumber (1 KG) from your cart. '
        'Your cart has 1 item, subtotal Dhs. 19.95.',
      );
      expect(cart.lines.single.title, 'Zespri Kiwi Sungold');
      expectGoodChips(reply);
    });

    test('"berries" matches Strawberry and Blueberry', () async {
      cart.add(strawberry, strawberry.variants[1]);
      final blueberry = priced(1, 'Blueberry', 3000);
      cart.add(blueberry, blueberry.variants.first);
      cart.add(kiwi, kiwi.variants.first);
      final reply = await brain.reply('take the berries out of my cart');
      expect(
        reply.text,
        'Removed Strawberry (1 KG) and Blueberry from your cart. Your cart '
        'has 1 item, subtotal Dhs. 19.95.',
      );
    });

    test('the last line removed leaves an empty cart', () async {
      cart.add(kiwi, kiwi.variants.first);
      final reply = await brain.reply('delete the kiwi from my cart');
      expect(
        reply.text,
        'Removed Zespri Kiwi Sungold (500 GM) from your cart. Your cart is '
        'empty now.',
      );
      expectGoodChips(reply);
    });

    test('nothing matching, nothing named, an empty cart', () async {
      var reply = await brain.reply('remove kiwi');
      expect(reply.text, 'Your cart is empty, so there is nothing to remove.');
      expectGoodChips(reply);

      cart.add(cucumber, cucumber.variants.first, quantity: 3);
      reply = await brain.reply('remove avocado');
      expect(
        reply.text,
        'I could not find avocado in your cart. Your cart has 3 items, '
        'subtotal Dhs. 7.50.',
      );
      expect(cart.quantityOf(2004), 3);
      expect(reply.actions.single, isA<OpenCartAction>());
      expectGoodChips(reply);

      reply = await brain.reply('remove');
      expect(
        reply.text,
        'Tell me what to remove, for example "Remove Cucumber". Your cart '
        'has 3 items, subtotal Dhs. 7.50.',
      );
      expect(reply.suggestions, contains('Remove Cucumber'));
      expect(cart.quantityOf(2004), 3);
      expect(api.calls, isEmpty);
    });
  });

  group('empty the cart', () {
    test('only asks; the button does the emptying', () async {
      final cucumber = sampleProducts()[2];
      cart.add(cucumber, cucumber.variants.first, quantity: 3);
      final reply = await brain.reply('empty my cart');
      expect(reply.text, 'This will remove all 3 items. Are you sure?');
      expect(reply.actions, hasLength(2));
      expect(reply.actions.first, isA<ClearCartAction>());
      expect(reply.actions.first.label, 'Yes, empty my cart');
      expect(reply.actions.last, isA<OpenCartAction>());
      expect(reply.actions.last.label, 'Review cart');
      expect(cart.itemCount, 3);
      expectGoodChips(reply);
    });

    test('one item and an empty cart', () async {
      var reply = await brain.reply('clear my cart');
      expect(reply.text, 'Your cart is already empty.');
      expect(reply.actions, isEmpty);

      final kiwi = sampleProducts().first;
      cart.add(kiwi, kiwi.variants.first);
      reply = await brain.reply('remove everything');
      expect(
        reply.text,
        'This will remove the 1 item in your cart. Are you sure?',
      );
      expect(cart.itemCount, 1);
    });
  });

  group('favourites', () {
    test('none, or no favourites store, explains the heart', () async {
      for (final b in [
        brain,
        AssistantBrain(api: api, cart: cart, favourites: FavouritesStore()),
      ]) {
        final reply = await b.reply('my favourites');
        expect(
          reply.text,
          'You have no favourites yet. Tap the heart on a product page to '
          'save it, and it will show up here.',
        );
        expect(reply.products, isEmpty);
        expectGoodChips(reply);
      }
      expect(api.calls, isEmpty);
    });

    test('the latest three, with prices from the store', () async {
      final favourites = FavouritesStore();
      final sample = sampleProducts();
      // Saved when the cucumber cost Dhs. 9.99; the store says 2.50 now.
      const oldCucumber = Product(
        id: 1003,
        title: 'Cucumber',
        handle: 'cucumber',
        variants: [Variant(id: 2004, title: '500 GM', priceCents: 999)],
      );
      favourites
        ..toggle(sample[0])
        ..toggle(sample[1])
        ..toggle(oldCucumber)
        ..toggle(sample[4]);
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
        favourites: favourites,
      ).reply('show my wishlist');
      expect(reply.text, 'You have 4 favourites. Here are the latest 3.');
      expect(reply.products.map((p) => p.title), [
        'Pink Passion Flower Bouquet',
        'Cucumber',
        'Australian Beef Cubes',
      ]);
      expect(reply.products[1].defaultVariant!.priceCents, 250);
      expect(api.calls, [
        'product(pink-passion-flower-bouquet)',
        'product(cucumber)',
        'product(australian-beef-cubes)',
      ]);
      expect(reply.actions.single, isA<OpenFavouritesAction>());
      expectGoodChips(reply);
    });

    test('a favourite the store no longer has is shown sold out', () async {
      final favourites = FavouritesStore()..toggle(priced(77, 'Old Fig', 500));
      final reply = await AssistantBrain(
        api: api,
        cart: cart,
        favourites: favourites,
      ).reply('saved');
      expect(reply.text, 'You have 1 favourite.');
      expect(reply.products.single.available, isFalse);
    });
  });

  group('store information', () {
    test('contact: only the facts from the website footer', () async {
      final reply = await brain.reply('Contact customer service');
      expect(
        reply.text,
        'You can reach Fresh Market customer service on 800 1 627538 '
        '(toll-free) or care@freshmarket.ae, 7 days a week, 8am to 11pm. '
        'The store is in Ras Al Khor, Dubai.',
      );
      final links = reply.actions.cast<OpenLinkAction>();
      expect(links.map((a) => a.label), [
        'Call 800 1 627538',
        'Email us',
        'Contact page',
      ]);
      expect(links.map((a) => a.uri), [
        'tel:8001627538',
        'mailto:care@freshmarket.ae',
        'https://testtfm.myshopify.com/pages/contact',
      ]);
      expect(
        reply.suggestions,
        containsAll(['Delivery information', 'Payment methods']),
      );
      expectGoodChips(reply);
      expect(api.calls, isEmpty);
    });

    test('payment: checkout only when the cart has something', () async {
      var reply = await brain.reply('How can I pay?');
      expect(
        reply.text,
        'The website lists Visa, Mastercard, Apple Pay and cash on '
        'delivery. You choose how to pay at checkout.',
      );
      expect(reply.actions, isEmpty);
      expectGoodChips(reply);

      final kiwi = sampleProducts().first;
      cart.add(kiwi, kiwi.variants.first);
      reply = await brain.reply('cash on delivery');
      expect(reply.actions.single, isA<CheckoutAction>());
      expectGoodChips(reply);
      expect(api.calls, isEmpty);
    });

    test('delivery: no fees, times or minimums', () async {
      final reply = await brain.reply('what is the delivery fee?');
      expect(
        reply.text,
        'Fresh Market delivers within the UAE. Many products are in the '
        '1Hr Express range. You choose the address and delivery time at '
        'checkout, where any fees are shown.',
      );
      for (final claim in ['Dhs', 'AED', 'minute', 'free', 'minimum']) {
        expect(reply.text, isNot(contains(claim)));
      }
      final express = reply.actions.first as OpenCollectionAction;
      expect(express.label, 'Open 1Hr Express');
      expect(express.handle, 'express');
      expect(express.title, '1Hr Express');
      final contact = reply.actions.last as SendMessageAction;
      expect(
        AssistantIntentParser.parse(contact.message),
        isA<ContactIntent>(),
      );
      expectGoodChips(reply);
      expect(api.calls, isEmpty);
    });

    test('brands: a search button per brand we love', () async {
      final reply = await brain.reply('which brands do you have?');
      expect(reply.text, 'Here are the brands we love.');
      final buttons = reply.actions.cast<OpenSearchAction>().toList();
      expect(buttons, hasLength(Catalog.brands.length));
      for (final (index, brand) in Catalog.brands.indexed) {
        expect(buttons[index].label, brand.name);
        expect(buttons[index].query, brand.searchTerm);
      }
      expectGoodChips(reply);
      expect(api.calls, isEmpty);

      // One brand is still a product search.
      final zespri = await brain.reply('Zespri');
      expect(zespri.products.single.title, 'Zespri Kiwi Sungold');
    });
  });

  group('suggestions', () {
    test('after add, offers, search and cart they follow the reply', () async {
      var reply = await brain.reply('Add 2 cucumbers');
      expect(reply.suggestions, [
        'Add 1 more Cucumber',
        'Open my cart',
        'Checkout',
        'Ideas for a fruit salad',
      ]);

      reply = await brain.reply('What is on offer?');
      expect(reply.suggestions, [
        'Add 1 Australian Beef Cubes',
        'What is popular?',
        'Open my cart',
      ]);

      reply = await brain.reply('find kiwi');
      expect(reply.suggestions, [
        'Cheapest kiwi',
        'Is kiwi in stock?',
        'Add 1 Zespri Kiwi Sungold',
      ]);

      reply = await brain.reply('open my cart');
      expect(reply.suggestions, [
        'Checkout',
        'Remove Cucumber',
        'Empty my cart',
      ]);
    });

    test('a product name in a chip keeps only plain words', () {
      expect(
        AssistantBrain.shortName('Zespri Kiwi Sungold'),
        'Zespri Kiwi Sungold',
      );
      expect(
        AssistantBrain.shortName('Pink Passion Flower Bouquet'),
        'Pink Passion Flower',
      );
      expect(
        AssistantBrain.shortName('Buy 1 Get 1 Free Mango 500 GM'),
        'Mango',
      );
      expect(
        AssistantBrain.shortName('Salt & Pepper Chips 150g'),
        'Salt Pepper Chips',
      );
      expect(
        AssistantBrain.shortName("Kid's Favourite Clear Honey"),
        "Kid's Honey",
      );
      expect(AssistantBrain.shortName('2 x 500 ML'), isNull);
    });

    test('every chip any reply makes parses to what it says, and an '
        '"Add 1" chip adds that product', () async {
      final shop = FakeShopifyApi(
        collections: {
          for (final handle in [
            'fresh-meat',
            'best-deals',
            'best-sellers',
            'berries',
            'local-uae',
            'hampers',
            'fruits',
          ])
            handle: shelf(),
        },
      );
      final favourites = FavouritesStore();
      for (final p in sampleProducts()) {
        favourites.toggle(p);
      }
      final full = CartStore();
      final cucumber = sampleProducts()[2];
      final kiwi = sampleProducts()[0];
      full
        ..add(cucumber, cucumber.variants.first, quantity: 3)
        ..add(kiwi, kiwi.variants.first);

      const messages = [
        'Add 2 cucumbers',
        'add 2kg cucumber',
        'add blueberry',
        'add dragonfruit',
        'add',
        'What is on offer?',
        'Show me berries',
        'Gift ideas',
        'Show local UAE produce',
        'fruit platter',
        'Show all categories',
        'Cheapest avocado',
        'avocado under 5',
        'cheapest',
        'How much is kiwi?',
        'how much is blueberry',
        'Is cucumber in stock?',
        'is blueberry available',
        'Ideas for a fruit salad',
        'Ideas for a BBQ',
        'recipe ideas',
        'my favourites',
        'Contact customer service',
        'payment methods',
        'delivery',
        'brands',
        'thanks',
        'bye',
        'find kiwi',
        'find avocado',
        'remove 1 cucumber',
        'remove avocado',
        'remove',
        'empty my cart',
        'checkout',
        'open my cart',
      ];
      final chips = <String>{};
      for (final cartNow in [full, CartStore()]) {
        final b = AssistantBrain(
          api: shop,
          cart: cartNow,
          favourites: favourites,
        );
        for (final message in messages) {
          final reply = await b.reply(message);
          expectGoodChips(reply);
          chips.addAll(reply.suggestions);
        }
      }
      for (final defaults in [
        ...AssistantBrain.defaultSuggestions,
        for (final option in AssistantBrain.quickOptions) option.message,
      ]) {
        expectChipParses(defaults);
      }
      expect(chips.length, greaterThan(20));

      // An "Add 1" chip finds and adds the product it names.
      for (final chip in chips.where((c) => c.startsWith('Add 1 '))) {
        final empty = CartStore();
        final reply = await AssistantBrain(api: shop, cart: empty).reply(chip);
        expect(reply.text, startsWith('Done. I added 1 × '), reason: chip);
        expect(empty.itemCount, 1, reason: chip);
      }
    });

    test('replies without their own chips fall back to the defaults', () async {
      for (final text in ['help', 'hi', 'show me']) {
        expect((await brain.reply(text)).suggestions, isEmpty, reason: text);
      }
      api.error = const NetworkException('offline');
      expect((await brain.reply('find kiwi')).suggestions, isEmpty);
    });
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

/// Records the limit of every search.
class _SearchLog extends FakeShopifyApi {
  _SearchLog(Map<String, List<Product>> collections)
    : super(collections: collections);

  final List<int> limits = [];

  @override
  Future<List<Product>> search(String query, {int limit = 10}) {
    limits.add(limit);
    return super.search(query, limit: limit);
  }
}

/// Slow searches that count how many run at the same time.
class _CountingApi extends _SearchLog {
  _CountingApi(super.collections);

  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<List<Product>> search(String query, {int limit = 10}) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return await super.search(query, limit: limit);
    } finally {
      inFlight--;
    }
  }
}

/// A search that always answers with the same products, like the live
/// store's search, which also suggests related products.
class _FixedSearch extends FakeShopifyApi {
  _FixedSearch(this.results);

  final List<Product> results;

  @override
  Future<List<Product>> search(String query, {int limit = 10}) async =>
      results.take(limit).toList();
}
