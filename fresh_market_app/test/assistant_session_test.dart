import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/assistant/assistant_session.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';

void main() {
  late FakeShopifyApi api;
  late CartStore cart;
  late AssistantSession session;

  setUp(() {
    api = FakeShopifyApi.sample();
    cart = CartStore();
    session = AssistantSession(minReplyDelay: Duration.zero);
  });

  test('starts with the greeting and its options grid', () {
    expect(session.messages, hasLength(1));
    expect(session.lastReply!.text, AssistantBrain.greeting);
    expect(session.lastReply!.showOptions, isTrue);
    expect(session.lastReply!.suggestions, isEmpty);
  });

  test(
    'send adds the question and the answer; lastReply is the answer',
    () async {
      await session.send('Add 2 cucumbers', api: api, cart: cart);
      expect(session.messages.map((m) => m.fromUser), [false, true, false]);
      expect(session.messages[1].text, 'Add 2 cucumbers');
      expect(
        session.lastReply!.text,
        'Done. I added 2 × Cucumber (500 GM) to your cart at \u20C3 2.50 each.',
      );
      expect(session.lastReply!.suggestions, contains('Open my cart'));
      expect(cart.itemCount, 2);

      // Blank messages are ignored.
      await session.send('   ', api: api, cart: cart);
      expect(session.messages, hasLength(3));
    },
  );

  test('send passes the favourites to the brain', () async {
    final kiwi = sampleProducts().first;
    final favourites = FavouritesStore()..toggle(kiwi);
    await session.send(
      'my favourites',
      api: api,
      cart: cart,
      favourites: favourites,
    );
    expect(session.lastReply!.text, 'You have 1 favourite.');
    expect(session.lastReply!.products.single.title, kiwi.title);

    await session.send('my favourites', api: api, cart: cart);
    expect(session.lastReply!.text, startsWith('You have no favourites'));
  });

  test('note, showOptions and reset; none while a reply loads', () async {
    session.note(const AssistantReply('Added 2 products.'));
    expect(session.lastReply!.text, 'Added 2 products.');

    session.showOptions();
    expect(session.lastReply!.text, AssistantBrain.optionsReply.text);
    expect(session.lastReply!.showOptions, isTrue);

    api.delay = const Duration(milliseconds: 20);
    final pending = session.send('find kiwi', api: api, cart: cart);
    expect(session.busy, isTrue);
    final before = session.messages.length;
    session.note(const AssistantReply('ignored'));
    session.showOptions();
    session.reset();
    expect(session.messages, hasLength(before));
    await pending;
    expect(session.lastReply!.text, 'I found this for "kiwi".');

    session.reset();
    expect(session.messages, hasLength(1));
    expect(session.lastReply!.text, AssistantBrain.greeting);
  });

  test('an unexpected failure ends with a reply, never stuck busy', () async {
    final broken = _BrokenApi();
    await session.send('find kiwi', api: broken, cart: cart);
    expect(session.busy, isFalse);
    expect(session.lastReply!.text, AssistantBrain.unexpectedError);

    // The assistant still answers afterwards.
    await session.send('find kiwi', api: api, cart: cart);
    expect(session.lastReply!.text, 'I found this for "kiwi".');
  });

  test('a chip from the latest reply acts on its product', () async {
    const box = Product(
      id: 30,
      title: 'Kiwi Green Zespri',
      handle: 'kiwi-box',
      variants: [Variant(id: 3030, title: 'Default Title', priceCents: 25200)],
    );
    const pack = Product(
      id: 31,
      title: 'Kiwi Green Zespri',
      handle: 'kiwi-pack',
      variants: [Variant(id: 3031, title: 'Default Title', priceCents: 1895)],
    );
    final shop = FakeShopifyApi(
      collections: {
        'fruits': [box, pack],
      },
    );
    await session.send('find kiwi green', api: shop, cart: cart);
    expect(session.lastReply!.suggestions, contains('Add 1 Kiwi Green Zespri'));
    await session.send('Add 1 Kiwi Green Zespri', api: shop, cart: cart);
    expect(cart.quantityOf(3030), 1);
    expect(cart.quantityOf(3031), 0);
  });

  test('a typed yes answers the latest "Are you sure?"', () async {
    final kiwi = sampleProducts().first;
    cart.add(kiwi, kiwi.variants.first);
    await session.send('Empty my cart', api: api, cart: cart);
    await session.send('yes', api: api, cart: cart);
    expect(
      session.lastReply!.text,
      'To empty your cart, tap "Yes, empty my cart" below.',
    );
    expect(cart.itemCount, 1);
  });

  test('done buttons are kept with the conversation until New chat', () {
    const action = OpenCartAction();
    session.note(const AssistantReply('Added', actions: [action]));
    final message = session.messages.last;
    expect(session.isDone(message, action), isFalse);
    expect(session.markDone(message, action), isTrue);
    expect(session.isDone(message, action), isTrue);
    expect(session.markDone(message, action), isFalse);

    session.reset();
    expect(session.isDone(message, action), isFalse);
  });
}

/// Fails with an error the brain does not turn into a reply.
class _BrokenApi extends FakeShopifyApi {
  @override
  Future<List<Product>> search(String query, {int limit = 10}) async =>
      throw StateError('broken');
}
