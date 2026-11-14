import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final products = sampleProducts();
  final kiwi = products[0]; // 500 GM 19.95, 1 KG 39.75
  final beef = products[1]; // 62.50, was 115.00
  final blueberry = products[3]; // sold out

  group('CartStore maths', () {
    test('adds, counts and totals by variant', () {
      final cart = CartStore();
      var notified = 0;
      cart.addListener(() => notified++);

      expect(cart.isEmpty, isTrue);
      expect(cart.hasAvailableLines, isFalse);

      cart.add(kiwi, kiwi.variants[0]);
      cart.add(kiwi, kiwi.variants[0]);
      cart.add(kiwi, kiwi.variants[1]);
      cart.add(beef, beef.variants[0], quantity: 3);

      expect(notified, 4);
      expect(cart.lines, hasLength(3));
      expect(cart.itemCount, 6);
      expect(cart.quantityOf(kiwi.variants[0].id), 2);
      expect(cart.quantityOfProduct(kiwi.id), 3);
      expect(cart.subtotalCents, 2 * 1995 + 3975 + 3 * 6250);

      final line = cart.lineOf(kiwi.variants[0].id)!;
      expect(line.title, 'Zespri Kiwi Sungold');
      expect(line.variantTitle, '500 GM');
      expect(line.lineTotalCents, 3990);
      expect(line.oldLineTotalCents, isNull);
      expect(line.detailLine, '500 g · \u20C3\u00A019.95 each');
      expect(line.size, '500 g');
      expect(line.origin, 'New Zealand');

      final sale = cart.lineOf(beef.variants[0].id)!;
      expect(sale.variantTitle, isNull);
      expect(sale.onSale, isTrue);
      expect(sale.oldLineTotalCents, 3 * 11500);
      expect(sale.detailLine, '\u20C3\u00A062.50 each');

      // At one unit the line total is the price: only the size is said.
      final one = cart.lineOf(kiwi.variants[1].id)!;
      expect(one.quantity, 1);
      expect(one.detailLine, '1 kg');
      expect(one.detailSemantics, '1 kg');
    });

    test('decrement to zero removes the line', () {
      final cart = CartStore();
      final id = kiwi.variants[0].id;
      cart.add(kiwi, kiwi.variants[0]);
      cart.increment(id);
      expect(cart.quantityOf(id), 2);
      cart.decrement(id);
      cart.decrement(id);
      expect(cart.quantityOf(id), 0);
      expect(cart.isEmpty, isTrue);
      // Stepping a line that is not in the cart does nothing.
      cart.increment(id);
      expect(cart.isEmpty, isTrue);
    });

    test('ignores sold-out variants and caps the quantity', () {
      final cart = CartStore();
      cart.add(blueberry, blueberry.variants[0]);
      expect(cart.isEmpty, isTrue);

      cart.add(beef, beef.variants[0], quantity: 500);
      expect(cart.quantityOf(beef.variants[0].id), CartStore.maxQuantity);
    });
  });

  group('what the order server says', () {
    test('a line it has sold out is marked and left out; a new price is '
        'kept, with the old one only while it is higher', () {
      final cart = CartStore();
      cart.add(kiwi, kiwi.variants[1], quantity: 2);
      cart.add(beef, beef.variants[0]);
      var notified = 0;
      cart.addListener(() => notified++);

      cart.markSoldOut(2002);
      expect(cart.lineOf(2002)!.available, isFalse);
      expect(cart.subtotalCents, 6250);
      expect(cart.hasAvailableLines, isTrue);
      cart.markSoldOut(2002);
      cart.markSoldOut(999);
      expect(notified, 1, reason: 'nothing new, nothing said');

      cart.updatePrice(2003, 7000);
      expect(cart.lineOf(2003)!.priceCents, 7000);
      expect(cart.lineOf(2003)!.onSale, isTrue, reason: 'was 115.00');
      cart.updatePrice(2003, 12000);
      expect(cart.lineOf(2003)!.onSale, isFalse);
      expect(cart.lineOf(2003)!.compareAtCents, isNull);
      expect(cart.subtotalCents, 12000);
    });
  });

  group('persistence', () {
    test('the cart comes back after a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final cart = CartStore(prefs: prefs);
      cart.add(kiwi, kiwi.variants[0], quantity: 2);
      cart.add(beef, beef.variants[0]);
      cart.decrement(beef.variants[0].id);

      final restored = CartStore(prefs: prefs);
      expect(restored.lines, hasLength(1));
      final line = restored.lines.single;
      expect(line.variantId, kiwi.variants[0].id);
      expect(line.quantity, 2);
      expect(line.title, 'Zespri Kiwi Sungold');
      expect(line.variantTitle, '500 GM');
      expect(line.priceCents, 1995);
      expect(line.imageUrl, kiwi.imageUrl);
      expect(restored.subtotalCents, 3990);

      restored.clear();
      expect(CartStore(prefs: prefs).isEmpty, isTrue);
    });

    test('the order key: kept until the outcome is known, for an hour '
        'after the last try, for the same account; kept on the device '
        '(a random key and a time, nothing personal)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final t0 = DateTime.utc(2026, 11, 14, 8);
      var n = 0;
      String next() => 'key-${++n}';
      final cart = CartStore(prefs: prefs)..add(kiwi, kiwi.variants[0]);
      var notified = 0;
      cart.addListener(() => notified++);

      expect(cart.pendingOrder, isNull);
      final first = cart.orderKey(account: 'sara@example.com', now: t0, newKey: next);
      expect(first, 'key-1');
      expect(notified, 0, reason: 'nothing on screen shows it');
      // Again (a retry, after an edit or a reopened checkout): the same.
      expect(
        cart.orderKey(
          account: 'sara@example.com',
          now: t0.add(const Duration(minutes: 50)),
          newKey: next,
        ),
        'key-1',
      );
      // An hour after the last try is still within the hour.
      expect(
        cart.orderKey(
          account: 'sara@example.com',
          now: t0.add(const Duration(minutes: 100)),
          newKey: next,
        ),
        'key-1',
      );

      // After a restart: read back, the account no longer known.
      final saved = prefs.getString(CartStore.pendingOrderPrefsKey)!;
      expect(saved, isNot(contains('sara')));
      final restored = CartStore(prefs: prefs);
      expect(restored.pendingOrder!.key, 'key-1');
      expect(restored.pendingOrder!.account, isNull);
      expect(
        restored.orderKey(
          account: 'sara@example.com',
          now: t0.add(const Duration(minutes: 110)),
          newKey: next,
        ),
        'key-1',
      );

      // Another account: a new key.
      expect(
        restored.orderKey(
          account: 'omar@example.com',
          now: t0.add(const Duration(minutes: 111)),
          newKey: next,
        ),
        'key-2',
      );
      // More than an hour after the last try: a new key.
      expect(
        restored.orderKey(
          account: 'omar@example.com',
          now: t0.add(const Duration(minutes: 172)),
          newKey: next,
        ),
        'key-3',
      );

      // Settled (201 or 409): gone, also from the device.
      restored.settleOrder();
      expect(restored.pendingOrder, isNull);
      expect(prefs.getString(CartStore.pendingOrderPrefsKey), isNull);
      expect(CartStore(prefs: prefs).pendingOrder, isNull);
      expect(
        restored.orderKey(now: t0.add(const Duration(hours: 3)), newKey: next),
        'key-4',
      );
      // Clearing the cart leaves the key (its order may exist).
      restored.clear();
      expect(restored.pendingOrder!.key, 'key-4');
    });

    test('a saved order key that cannot be read is dropped', () async {
      SharedPreferences.setMockInitialValues({
        CartStore.pendingOrderPrefsKey: '{"key": 3}',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(CartStore(prefs: prefs).pendingOrder, isNull);
    });

    test('a saved cart that cannot be read is dropped', () async {
      SharedPreferences.setMockInitialValues({CartStore.prefsKey: 'not json'});
      final prefs = await SharedPreferences.getInstance();
      expect(CartStore(prefs: prefs).isEmpty, isTrue);
    });

    test('favourites toggle and come back after a restart', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final favourites = FavouritesStore(prefs: prefs);
      expect(favourites.toggle(kiwi), isTrue);
      expect(favourites.toggle(beef), isTrue);
      expect(favourites.toggle(kiwi), isFalse);
      expect(favourites.contains(beef.id), isTrue);
      expect(favourites.contains(kiwi.id), isFalse);

      final restored = FavouritesStore(prefs: prefs);
      expect(restored.count, 1);
      final product = restored.products.single;
      expect(product.title, 'Australian Beef Cubes');
      expect(product.defaultVariant!.salePercent, 46);
      expect(product.imageUrl, beef.imageUrl);
    });
  });
}
