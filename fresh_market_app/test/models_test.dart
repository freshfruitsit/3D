import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/models/collection.dart';
import 'package:fresh_market_app/models/money.dart';
import 'package:fresh_market_app/models/product.dart';

import 'support/test_app.dart';

void main() {
  group('formatMoney', () {
    test('formats minor units the way the store does', () {
      expect(formatMoney(1250), '\u20C3 12.50');
      expect(formatMoney(250), '\u20C3 2.50');
      expect(formatMoney(5), '\u20C3 0.05');
      expect(formatMoney(0), '\u20C3 0.00');
      expect(formatMoney(30000), '\u20C3 300.00');
      expect(formatMoney(125000), '\u20C3 1,250.00');
      expect(formatMoney(123456789), '\u20C3 1,234,567.89');
      expect(formatMoney(-500), '-\u20C3 5.00');
    });

    test('the Dirham sign is U+20C3, then a space', () {
      expect(dirhamSign, '\u20C3');
      expect(dirhamSign.runes.single, 0x20C3);
      expect(formatMoney(1250).startsWith('$dirhamSign '), isTrue);
    });

    test('screen readers hear AED; the bare amount has no sign', () {
      expect(moneySemantics(1250), 'AED 12.50');
      expect(moneySemantics(125000), 'AED 1,250.00');
      expect(moneySemantics(-500), '-AED 5.00');
      expect(formatAmount(1250), '12.50');
      expect(formatAmount(123456789), '1,234,567.89');
    });

    test('parseMoney reads every storefront shape', () {
      expect(parseMoney('24.00'), 2400);
      expect(parseMoney('19.95'), 1995);
      expect(parseMoney('0.29'), 29);
      expect(parseMoney(2050), 2050);
      expect(parseMoney(''), isNull);
      expect(parseMoney(null), isNull);
      expect(moneyToDecimalString(1995), '19.95');
      expect(moneyToDecimalString(300), '3.00');
    });
  });

  group('Product from a collection page', () {
    late List<Product> products;

    setUp(() {
      products = Product.listFromJson(
        loadFixture('collection_products.json') as Map<String, dynamic>,
      );
    });

    test('parses products, variants, images and options', () {
      expect(products, hasLength(3));
      final kiwi = products.first;
      expect(kiwi.title, 'Zespri Kiwi Sungold');
      expect(kiwi.handle, 'zespri-kiwi-sungold');
      expect(kiwi.vendor, 'Vegetable Souk Fruits');
      expect(kiwi.variants.map((v) => v.title), ['500 GM', '1 KG']);
      expect(kiwi.variants.map((v) => v.priceCents), [1995, 3975]);
      expect(kiwi.variants.first.priceText, '\u20C3 19.95');
      expect(kiwi.variants.first.onSale, isFalse);
      expect(kiwi.variants.first.salePercent, isNull);
      expect(kiwi.imageUrl, startsWith('https://cdn.shopify.com/'));
      expect(kiwi.optionName, 'Weight');
      expect(kiwi.hasVariantChoice, isTrue);
      expect(kiwi.available, isTrue);
    });

    test('derives origin, facts and the size line from tags', () {
      final kiwi = products.first;
      expect(kiwi.origin, 'New Zealand');
      expect(kiwi.isExpress, isTrue);
      expect(kiwi.isByAir, isTrue);
      expect(kiwi.isLocal, isFalse);
      expect(kiwi.facts, [ProductFact.express, ProductFact.byAir]);
      expect(kiwi.sizeLine(), 'New Zealand · 500 GM');
      expect(kiwi.sizeLine(kiwi.variants[1]), 'New Zealand · 1 KG');

      final sweetPotato = products[2];
      expect(sweetPotato.origin, isNull);
      expect(sweetPotato.sizeLine(), '500 GM');
    });

    test('strips HTML from the description', () {
      final text = products.first.description;
      expect(text, isNot(contains('<')));
      expect(text, contains('Usage Instructions'));
      expect(text, contains('• Wash kiwi before cutting'));
      expect(text, isNot(contains('\n\n\n')));
    });

    test('survives a round trip through toJson', () {
      final kiwi = products.first;
      final copy = Product.fromJson(kiwi.toJson());
      expect(copy.id, kiwi.id);
      expect(copy.title, kiwi.title);
      expect(copy.tags, kiwi.tags);
      expect(copy.images, kiwi.images);
      expect(copy.variants.map((v) => v.id), kiwi.variants.map((v) => v.id));
      expect(copy.variants.map((v) => v.priceCents),
          kiwi.variants.map((v) => v.priceCents));
      expect(copy.optionName, 'Weight');
    });
  });

  group('Product on sale', () {
    test('computes the sale percentage only when the old price is higher', () {
      final products = Product.listFromJson(
        loadFixture('sale_products.json') as Map<String, dynamic>,
      );
      final beef = products.first;
      final variant = beef.defaultVariant!;
      expect(variant.isDefault, isTrue);
      expect(variant.label, isNull);
      expect(variant.priceCents, 6250);
      expect(variant.compareAtCents, 11500);
      expect(variant.onSale, isTrue);
      expect(variant.salePercent, 46);
      expect(variant.oldPriceCents, 11500);
      expect(beef.hasVariantChoice, isFalse);

      const notReally = Variant(
          id: 1, title: 'x', priceCents: 500, compareAtCents: 500);
      expect(notReally.onSale, isFalse);
      expect(notReally.salePercent, isNull);
      expect(notReally.oldPriceCents, isNull);
    });
  });

  group('Product from the single-product endpoints', () {
    test('/products/x.js: integer prices, protocol-relative images', () {
      final p = Product.fromJson(
        loadFixture('product_js.json') as Map<String, dynamic>,
      );
      expect(p.title, 'Strawberry');
      expect(p.handle, 'strawberry-south-africa-250g-pack');
      expect(p.variants, hasLength(1));
      expect(p.variants.first.priceCents, 2050);
      expect(p.variants.first.available, isTrue);
      expect(p.variants.first.onSale, isFalse);
      expect(p.imageUrl, startsWith('https://cdn.shopify.com/'));
      expect(p.origin, 'South Africa');
      expect(p.sizeLine(), 'South Africa');
      expect(p.optionName, 'Options');
      expect(p.description, contains('Fresh, vibrant strawberries'));
    });

    test('/products/x.json: comma-separated tags, empty old price', () {
      final json = loadFixture('product_json.json') as Map<String, dynamic>;
      final p = Product.fromJson(json['product'] as Map<String, dynamic>);
      expect(p.tags, contains('origin:South Africa'));
      expect(p.tags, contains('1hr-delivery'));
      expect(p.variants.first.priceCents, 2050);
      expect(p.variants.first.compareAtCents, isNull);
    });
  });

  test('default variant skips sold-out variants', () {
    const p = Product(id: 1, title: 'p', handle: 'p', variants: [
      Variant(id: 1, title: '250 GM', priceCents: 100, available: false),
      Variant(id: 2, title: '1 KG', priceCents: 300),
    ]);
    expect(p.defaultVariant!.id, 2);
    expect(p.available, isTrue);

    const soldOut = Product(id: 2, title: 'p', handle: 'p', variants: [
      Variant(id: 3, title: 'Default Title', priceCents: 100, available: false),
    ]);
    expect(soldOut.defaultVariant!.id, 3);
    expect(soldOut.available, isFalse);
  });

  test('local products without an origin tag read as UAE', () {
    const p = Product(id: 1, title: 'p', handle: 'p', tags: ['Local']);
    expect(p.origin, 'UAE');
    expect(p.facts, [ProductFact.local]);
  });

  test('shopifyImageUrl adds the width parameter', () {
    expect(
      shopifyImageUrl('https://cdn.shopify.com/a/b.jpg?v=12', width: 360),
      'https://cdn.shopify.com/a/b.jpg?v=12&width=360',
    );
    expect(
      shopifyImageUrl('//cdn.shopify.com/a/b.jpg', width: 240),
      'https://cdn.shopify.com/a/b.jpg?width=240',
    );
    expect(shopifyImageUrl('https://x/y.jpg'), 'https://x/y.jpg');
  });

  test('stripHtml decodes entities and keeps paragraphs', () {
    expect(
      stripHtml('<p>Apples &amp; pears</p><p>It&#39;s&nbsp;fresh<br>today</p>'),
      "Apples & pears\n\nIt's fresh\ntoday",
    );
    expect(stripHtml(''), '');
  });

  test('Collection.fromJson', () {
    final json = loadFixture('collections.json') as Map<String, dynamic>;
    final list = [
      for (final c in json['collections'] as List)
        Collection.fromJson(c as Map<String, dynamic>),
    ];
    expect(list.first.handle, 'express');
    expect(list.first.imageUrl, isNull);
    expect(list.first.productsCount, 332);
    expect(list[1].imageUrl, startsWith('https://cdn.shopify.com/'));
  });
}
