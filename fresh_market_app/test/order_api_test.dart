import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/models/order.dart';
import 'package:fresh_market_app/services/order_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _bay = DeliveryConfig.areaNamed('Business Bay')!;

const _order = OrderRequest(
  lines: [OrderLineRequest(variantId: 2001, quantity: 2)],
  delivery: DeliveryRequest(
    mode: DeliveryMode.market,
    area: DeliveryArea(
      name: 'Business Bay',
      emirate: Emirate.dubai,
      lat: 25.185,
      lng: 55.265,
    ),
    promise: 'Today within 6 hours',
    pin: '25.18500,55.26500',
  ),
  address: OrderAddress(
    firstName: 'Sara',
    lastName: 'Ahmed',
    address1: 'Bay Square, Building 5',
    address2: 'Flat 302',
    city: 'Business Bay',
    emirate: Emirate.dubai,
    phone: '+971501234567',
  ),
  instructions: 'Call when you arrive',
  expectedTotalFils: 6490,
);

http.Response _json(int status, Object body, {Map<String, String>? headers}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?headers},
    );

const _created = {
  'orderId': 'gid://shopify/Order/1',
  'orderName': '#1001',
  'totalFils': 6490,
  'deliveryPromise': 'Today within 6 hours',
  'paymentMethod': 'Cash on Delivery',
};

/// An [OrderApi] whose server answers with [answers] in turn, recording
/// the requests and the waits between retries.
({OrderApi api, List<http.Request> requests, List<Duration> waits}) _api(
  List<FutureOr<http.Response> Function(http.Request)> answers, {
  Duration timeout = const Duration(seconds: 20),
}) {
  final requests = <http.Request>[];
  final waits = <Duration>[];
  final api = OrderApi(
    base: 'https://orders.example.com/',
    client: MockClient((request) async {
      requests.add(request);
      return answers.removeAt(0)(request);
    }),
    timeout: timeout,
    sleep: (d) async => waits.add(d),
  );
  return (api: api, requests: requests, waits: waits);
}

Future<PlacedOrder> _place(OrderApi api, {String key = 'key-1'}) =>
    api.placeOrder(_order, accessToken: 'tok', idempotencyKey: key);

void main() {
  group('setup', () {
    test('no ORDER_API_BASE (or a bad one): ordering is unavailable', () {
      expect(OrderApi().available, isFalse, reason: 'none in tests');
      expect(OrderApi(base: '').available, isFalse);
      expect(OrderApi(base: 'ftp://x').available, isFalse);
      expect(OrderApi(base: 'not a url').available, isFalse);
      expect(
        OrderApi(base: '').quote(
          lines: const [],
          delivery: DeliveryRequest(mode: DeliveryMode.market, area: _bay),
        ),
        throwsA(isA<OrderingUnavailable>()),
      );
      expect(OrderApi(base: 'https://o.example.com/').available, isTrue);
    });

    test('Idempotency-Keys are random v4 UUIDs', () {
      final key = OrderApi.newIdempotencyKey(Random(1));
      expect(
        key,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
            r'[0-9a-f]{12}$',
          ),
        ),
      );
      expect(OrderApi.newIdempotencyKey(), isNot(OrderApi.newIdempotencyKey()));
    });

    test('health: the version', () async {
      final t = _api([
        (_) => _json(200, {'ok': true, 'version': '1.0.0'}),
      ]);
      expect(await t.api.health(), '1.0.0');
      expect(
        t.requests.single.url.toString(),
        'https://orders.example.com/api/health',
      );
    });
  });

  group('quote', () {
    test('sends the lines, mode and area; reads the quote', () async {
      final t = _api([
        (_) => _json(200, {
          'lines': [
            {
              'variantId': 2001,
              'title': 'Zespri Kiwi Sungold',
              'variantTitle': '500 GM',
              'quantity': 2,
              'unitPriceFils': 1995,
              'lineTotalFils': 3990,
              'available': true,
            },
            {
              'variantId': 'gid://shopify/ProductVariant/2003',
              'title': 'Australian Beef Cubes',
              'variantTitle': null,
              'quantity': 1,
              'unitPriceFils': 6250,
              'lineTotalFils': 0,
              'available': false,
            },
          ],
          'subtotalFils': 3990,
          'deliveryFeeFils': 2500,
          'totalFils': 6490,
          'currency': 'AED',
          'deliveryPromise': 'Today within 6 hours',
          'problems': [
            {'variantId': 2003, 'kind': 'sold_out', 'message': 'Sold out.'},
            {'variantId': null, 'kind': 'not_express', 'message': 'No.'},
            {'variantId': 1, 'kind': 'something_new', 'message': 'New.'},
          ],
          'minOrderFils': 0,
        }),
      ]);
      final quote = await t.api.quote(
        lines: const [
          OrderLineRequest(variantId: 2001, quantity: 2),
          OrderLineRequest(variantId: 2003, quantity: 1),
        ],
        delivery: DeliveryRequest(mode: DeliveryMode.express, area: _bay),
      );
      final request = t.requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://orders.example.com/api/quote');
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(request.headers.containsKey('authorization'), isFalse);
      expect(jsonDecode(request.body), {
        'lines': [
          {'variantId': 2001, 'quantity': 2},
          {'variantId': 2003, 'quantity': 1},
        ],
        'delivery': {
          'mode': 'express',
          'area': {
            'name': 'Business Bay',
            'emirate': 'dubai',
            'lat': 25.185,
            'lng': 55.265,
          },
        },
      });
      expect(quote.totalFils, 6490);
      expect(quote.itemCount, 2);
      expect(quote.lines[1].variantId, 2003);
      expect(quote.lines[1].available, isFalse);
      expect(quote.availableLines, hasLength(1));
      expect(quote.problems.map((p) => p.kind), [
        QuoteProblemKind.soldOut,
        QuoteProblemKind.notExpress,
        QuoteProblemKind.other,
      ]);
      expect(quote.problems[1].variantId, isNull);
      expect(quote.belowMinimum, isFalse);
    });

    test(
      'a 5xx, an unreadable answer and no answer are errors to retry',
      () async {
        final delivery = DeliveryRequest(mode: DeliveryMode.market, area: _bay);
        const lines = [OrderLineRequest(variantId: 1, quantity: 1)];
        var t = _api([
          (_) => _json(503, {'retryable': true}),
        ]);
        expect(
          t.api.quote(lines: lines, delivery: delivery),
          throwsA(isA<OrderServerError>()),
        );
        t = _api([(_) => http.Response('<html>', 200)]);
        expect(
          t.api.quote(lines: lines, delivery: delivery),
          throwsA(isA<OrderNetworkError>()),
        );
        t = _api([(_) => throw http.ClientException('offline')]);
        expect(
          t.api.quote(lines: lines, delivery: delivery),
          throwsA(isA<OrderNetworkError>()),
        );
      },
    );
  });

  group('placeOrder', () {
    test(
      '201: the bearer token, the Idempotency-Key and the whole order',
      () async {
        final t = _api([(_) => _json(201, _created)]);
        final placed = await _place(t.api, key: 'f3b1c2d4-0000-4000-8000-1234');
        final request = t.requests.single;
        expect(request.url.path, '/api/orders');
        expect(request.headers['authorization'], 'Bearer tok');
        expect(
          request.headers['idempotency-key'],
          'f3b1c2d4-0000-4000-8000-1234',
        );
        expect(jsonDecode(request.body), {
          'lines': [
            {'variantId': 2001, 'quantity': 2},
          ],
          'delivery': {
            'mode': 'market',
            'area': {
              'name': 'Business Bay',
              'emirate': 'dubai',
              'lat': 25.185,
              'lng': 55.265,
            },
            'promise': 'Today within 6 hours',
            'pin': '25.18500,55.26500',
          },
          'address': {
            'firstName': 'Sara',
            'lastName': 'Ahmed',
            'address1': 'Bay Square, Building 5',
            'address2': 'Flat 302',
            'city': 'Business Bay',
            'emirate': 'dubai',
            'phone': '+971501234567',
          },
          'instructions': 'Call when you arrive',
          'expectedTotalFils': 6490,
        });
        expect(placed.orderName, '#1001');
        expect(placed.totalFils, 6490);
        expect(placed.paymentMethod, 'Cash on Delivery');
      },
    );

    test('401, 409, 422 and 429 are said, never retried', () async {
      var t = _api([
        (_) => _json(401, {'error': 'unauthorized'}),
      ]);
      await expectLater(_place(t.api), throwsA(isA<OrderUnauthorized>()));
      expect(t.requests, hasLength(1));

      t = _api([
        (_) => _json(409, {
          'error': 'quote_changed',
          'problems': [
            {'variantId': 2001, 'kind': 'qty_reduced', 'message': 'Only 1.'},
          ],
          'quote': {
            'lines': [],
            'subtotalFils': 0,
            'deliveryFeeFils': 0,
            'totalFils': 0,
            'deliveryPromise': '',
            'problems': [],
          },
        }),
      ]);
      final changed = await _place(t.api)
          .then<Object>((_) => 'placed', onError: (Object e) => e);
      expect(changed, isA<OrderChanged>());
      expect(
        (changed as OrderChanged).problems.single.kind,
        QuoteProblemKind.qtyReduced,
      );
      expect(changed.quote, isNotNull);
      expect(t.requests, hasLength(1));

      t = _api([
        (_) => _json(422, {
          'error': 'invalid',
          'field': 'address.phone',
          'message': 'Add a mobile number so the driver can call you.',
        }),
      ]);
      final invalid = await _place(t.api)
          .then<Object>((_) => 'placed', onError: (Object e) => e);
      expect(invalid, isA<OrderInvalid>());
      expect((invalid as OrderInvalid).field, 'address.phone');
      expect(
        invalid.userMessage,
        'Add a mobile number so the driver can call you.',
      );

      t = _api([
        (_) => _json(
          429,
          {'error': 'rate_limited', 'retryAfterSeconds': 60},
          headers: {'retry-after': '120'},
        ),
      ]);
      final limited = await _place(t.api)
          .then<Object>((_) => 'placed', onError: (Object e) => e);
      expect(
        (limited as OrderRateLimited).retryAfter,
        const Duration(seconds: 120),
      );
      expect(t.requests, hasLength(1));
    });

    test('a retryable 5xx is sent again with the same key, at most twice, '
        'then the error', () async {
      var t = _api([
        (_) => _json(503, {'retryable': true}),
        (_) => _json(503, {'retryable': true}),
        (_) => _json(201, _created),
      ]);
      expect((await _place(t.api, key: 'k-same')).orderName, '#1001');
      expect(t.requests.map((r) => r.headers['idempotency-key']), [
        'k-same',
        'k-same',
        'k-same',
      ]);
      expect(t.waits, const [Duration(seconds: 1), Duration(seconds: 3)]);

      t = _api([
        (_) => _json(503, {'retryable': true}),
        (_) => _json(502, {}),
        (_) => _json(503, {'retryable': true}),
      ]);
      await expectLater(_place(t.api), throwsA(isA<OrderServerError>()));
      expect(t.requests, hasLength(3));

      // Set up wrongly: not retried.
      t = _api([
        (_) => _json(500, {'retryable': false}),
      ]);
      await expectLater(_place(t.api), throwsA(isA<OrderServerError>()));
      expect(t.requests, hasLength(1));
    });

    test('a timeout or no answer is retried with the same key (the server '
        'never makes the order twice)', () async {
      var calls = 0;
      final t = _api([
        (_) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return _json(201, _created);
        },
        (_) => throw http.ClientException('connection reset'),
        (_) => _json(201, _created),
      ], timeout: const Duration(milliseconds: 50));
      final placed = await _place(t.api, key: 'k-timeout');
      expect(placed.orderName, '#1001');
      expect(calls, 1);
      expect(t.requests.map((r) => r.headers['idempotency-key']).toSet(), {
        'k-timeout',
      });
      expect(t.requests, hasLength(3));
    });

    test('an unreadable 201 is asked again (the same key brings the same '
        'answer)', () async {
      final t = _api([
        (_) => http.Response('oops', 201),
        (_) => _json(201, _created),
      ]);
      expect((await _place(t.api)).orderName, '#1001');
      expect(t.requests, hasLength(2));
    });
  });
}
