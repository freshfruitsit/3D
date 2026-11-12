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
      expect(cart.checkoutUrl, isNull);

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
      expect(line.detailLine, '500 GM · Dhs. 19.95 each');
      expect(line.origin, 'New Zealand');

      final sale = cart.lineOf(beef.variants[0].id)!;
      expect(sale.variantTitle, isNull);
      expect(sale.onSale, isTrue);
      expect(sale.oldLineTotalCents, 3 * 11500);
      expect(sale.detailLine, 'Dhs. 62.50 each');
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

  group('checkout URL', () {
    test('lists variant:quantity pairs in cart order', () {
      final cart = CartStore();
      cart.add(kiwi, kiwi.variants[1], quantity: 2);
      cart.add(beef, beef.variants[0]);
      expect(
        cart.checkoutUrl.toString(),
        'https://testtfm.myshopify.com/cart/2002:2,2003:1',
      );
    });

    test('skips empty quantities; null when nothing is left', () {
      expect(
        CartStore.buildCheckoutUrl({67691515740237: 3, 5: 0}).toString(),
        'https://testtfm.myshopify.com/cart/67691515740237:3',
      );
      expect(CartStore.buildCheckoutUrl({}), isNull);
      expect(CartStore.buildCheckoutUrl({5: 0}), isNull);
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
