import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/assistant/assistant_intent.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';

/// A UTC moment at UAE wall-clock [hour]:[minute] (UTC+4).
DateTime uae(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 13, hour - 4, minute);

DeliveryStore deliveryAt(String area, DateTime at) =>
    DeliveryStore(now: () => at, refreshEvery: null)
      ..setArea(DeliveryConfig.areaNamed(area)!);

/// Same-day cut-off questions get the delivery answer, which states the
/// cut-off in the website delivery bar's words.
void main() {
  const questions = [
    'what is the cut off time',
    'cutoff time?',
    'Cut-off for same day?',
    'when is the last order for today',
  ];

  test('cut-off questions parse as delivery questions', () {
    for (final q in questions) {
      expect(AssistantIntentParser.parse(q), isA<DeliveryIntent>(), reason: q);
    }
  });

  test('before the cut-off: how long same-day stays open', () async {
    for (final q in questions) {
      final api = FakeShopifyApi.sample();
      final reply = await AssistantBrain(
        api: api,
        cart: CartStore(),
        delivery: deliveryAt('Business Bay', uae(10)),
      ).reply(q);
      expect(
        reply.text,
        'Delivering to Business Bay, Dubai: Today within 6 hours, by 4 PM. '
        'Same-day closes in 8h 0m (cut-off 6 PM). '
        'Express: 30–40 min for items marked Express. '
        'Any delivery fee is shown at checkout.',
        reason: q,
      );
      expect(api.calls, isEmpty, reason: q);
    }
  });

  test('after the cut-off: same-day is closed', () async {
    final reply = await AssistantBrain(
      api: FakeShopifyApi.sample(),
      cart: CartStore(),
      delivery: deliveryAt('Business Bay', uae(23)),
    ).reply('what is the cut off time');
    expect(
      reply.text,
      'Delivering to Business Bay, Dubai: Tomorrow morning before 11 AM. '
      'Same-day orders closed at 6 PM. '
      'Express: closed right now (it runs 8 AM to 10 PM). '
      'Any delivery fee is shown at checkout.',
    );
  });
}
