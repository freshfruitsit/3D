import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

http.Response jsonResponse(String body, [int status = 200]) => http.Response
    .bytes(utf8.encode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('HttpShopifyApi', () {
    test('loads a collection page from the right URL', () async {
      late Uri requested;
      final api = HttpShopifyApi(client: MockClient((request) async {
        requested = request.url;
        return jsonResponse(fixture('collection_products.json'));
      }));

      final products = await api.collectionProducts('best-deals', page: 2);

      expect(requested.host, 'testtfm.myshopify.com');
      expect(requested.path, '/collections/best-deals/products.json');
      expect(requested.queryParameters, {'limit': '24', 'page': '2'});
      expect(products.map((p) => p.title),
          ['Zespri Kiwi Sungold', 'Avocado Hass Periban Unripe', 'Sweet Potato']);
    });

    test('search loads each suggestion as a full product, once', () async {
      final paths = <String>[];
      final api = HttpShopifyApi(client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/search/suggest.json') {
          expect(request.url.queryParameters['q'], 'strawberry');
          expect(request.url.queryParameters['resources[type]'], 'product');
          return jsonResponse(fixture('search_suggest.json'));
        }
        if (request.url.path ==
            '/products/strawberry-south-africa-250g-pack.js') {
          return jsonResponse(fixture('product_js.json'));
        }
        return jsonResponse('{}', 404);
      }));

      final results = await api.search(' strawberry ');
      // Suggestions whose product fails to load are dropped.
      expect(results, hasLength(1));
      expect(results.single.variants.single.priceCents, 2050);

      paths.clear();
      await api.product('strawberry-south-africa-250g-pack');
      expect(paths, isEmpty, reason: 'served from the cache');

      expect(await api.search('   '), isEmpty);
    });

    test('maps failures to typed errors', () async {
      final notFound = HttpShopifyApi(
          client: MockClient((_) async => jsonResponse('{}', 404)));
      await expectLater(
        notFound.collectionProducts('nope'),
        throwsA(isA<HttpStatusException>()
            .having((e) => e.isNotFound, 'isNotFound', isTrue)),
      );

      final offline = HttpShopifyApi(
          client: MockClient(
              (_) async => throw const SocketException('no route')));
      await expectLater(
          offline.collections(), throwsA(isA<NetworkException>()));

      final garbage = HttpShopifyApi(
          client: MockClient((_) async => jsonResponse('<html>')));
      await expectLater(
          garbage.collections(), throwsA(isA<ParseException>()));

      final slow = HttpShopifyApi(
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return jsonResponse('{}');
        }),
      );
      await expectLater(
        slow.product('x'),
        throwsA(isA<NetworkException>()
            .having((e) => e.userMessage, 'userMessage', isNotEmpty)),
      );
    });
  });

  group('FakeShopifyApi', () {
    test('pages, searches and fails on demand', () async {
      final api = FakeShopifyApi.sample();
      expect(await api.collectionProducts('fruits', limit: 4), hasLength(4));
      expect(await api.collectionProducts('fruits', page: 2, limit: 4),
          hasLength(2));
      expect(await api.collectionProducts('fruits', page: 3, limit: 4),
          isEmpty);
      expect((await api.search('kiwi')).single.handle, 'zespri-kiwi-sungold');
      expect((await api.product('cucumber')).title, 'Cucumber');
      await expectLater(api.collectionProducts('unknown'),
          throwsA(isA<HttpStatusException>()));

      api.error = const NetworkException('offline');
      await expectLater(api.search('kiwi'), throwsA(isA<NetworkException>()));
      expect(api.calls.last, 'search(kiwi)');
    });
  });
}
