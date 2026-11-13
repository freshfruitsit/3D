import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/assistant/assistant_session.dart';
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
        'Done. I added 2 × Cucumber (500 GM) to your cart at Dhs. 2.50 each.',
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
}
