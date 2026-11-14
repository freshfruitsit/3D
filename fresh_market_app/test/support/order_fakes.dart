import 'dart:async';
import 'dart:convert';

import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/profile/profile_vault.dart';
import 'package:fresh_market_app/services/customer_account_api.dart';
import 'package:fresh_market_app/services/customer_auth.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/order_api.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An unsigned OpenID Connect ID token (JWT) carrying [email] (tests).
String fakeIdToken([String? email = 'sara@example.com']) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.'
      '${part({'sub': 'gid://shopify/Customer/1', 'email': ?email})}.sig';
}

/// Tokens as Shopify would hand them over (tests).
AuthTokens testTokens({
  String access = 'access-1',
  String? refresh = 'refresh-1',
  String? email = 'sara@example.com',
  Duration validFor = const Duration(hours: 1),
  DateTime? now,
}) {
  final id = fakeIdToken(email);
  return AuthTokens(
    accessToken: access,
    refreshToken: refresh,
    idToken: id,
    expiresAt: (now ?? DateTime.now()).add(validFor).toUtc(),
    email: AuthTokens.emailInIdToken(id),
  );
}

/// Stands in for Shopify's sign-in (flutter_appauth): hands out tokens,
/// or throws what a test sets, and counts the calls.
class FakeOAuthClient implements OAuthClient {
  FakeOAuthClient({this.email = 'sara@example.com'});

  String? email;
  int authorizeCalls = 0;
  int refreshCalls = 0;

  /// Thrown by the next [authorize] (then cleared).
  AuthException? authorizeError;

  /// Thrown by every [refresh] while set.
  AuthException? refreshError;

  /// While set, [authorize] waits for it (the Custom Tab is open).
  Completer<void>? holdAuthorize;

  @override
  Future<AuthTokens> authorize() async {
    authorizeCalls++;
    await holdAuthorize?.future;
    final error = authorizeError;
    authorizeError = null;
    if (error != null) throw error;
    return testTokens(access: 'access-$authorizeCalls', email: email);
  }

  @override
  Future<AuthTokens> refresh(AuthTokens tokens) async {
    refreshCalls++;
    final error = refreshError;
    if (error != null) throw error;
    return testTokens(
      access: 'refreshed-$refreshCalls',
      refresh: tokens.refreshToken,
      email: tokens.email,
    );
  }
}

/// Records the end-session calls Shopify gets (sign-out).
class EndSessionRecorder {
  final List<Uri> calls = [];
  bool fail = false;

  http.Client get client => MockClient((request) async {
    calls.add(request.url);
    if (fail) throw http.ClientException('offline');
    return http.Response('', 200);
  });
}

/// A session that can sign in through [client] (signed out to start).
AccountSession signedOutSession({
  FakeOAuthClient? client,
  ProfileVault? vault,
  EndSessionRecorder? endSession,
}) => AccountSession(
  auth: CustomerAuth(
    client: client ?? FakeOAuthClient(),
    vault: vault ?? MemoryProfileVault(),
    httpClient: (endSession ?? EndSessionRecorder()).client,
  ),
);

/// A session signed in as [email] (its tokens already saved), read.
Future<AccountSession> signedInSession({
  String? email = 'sara@example.com',
  FakeOAuthClient? client,
  MemoryProfileVault? vault,
  EndSessionRecorder? endSession,
  Duration validFor = const Duration(hours: 1),
}) async {
  final store =
      vault ??
      MemoryProfileVault(
        jsonEncode(testTokens(email: email, validFor: validFor).toJson()),
      );
  final session = AccountSession(
    auth: CustomerAuth(
      client: client ?? FakeOAuthClient(email: email),
      vault: store,
      httpClient: (endSession ?? EndSessionRecorder()).client,
    ),
  );
  await session.load();
  return session;
}

/// The owner's order server in tests: quotes the sample products at their
/// prices (delivery AED 25, free from AED 200) and answers orders with
/// whatever [orderAnswers] holds next (201 by default). Every request is
/// kept.
class FakeOrderServer {
  FakeOrderServer({List<Product>? products})
    : _products = products ?? sampleProducts();

  final List<Product> _products;
  final List<http.Request> requests = [];

  /// Variant ids the quote calls sold out.
  final Set<int> soldOut = {};

  /// Variant ids with less stock: id -> units left.
  final Map<int, int> stock = {};

  /// Prices the store changed to: id -> fils.
  final Map<int, int> prices = {};

  /// Answers for `POST /api/orders`, used in turn; 201 when empty.
  final List<FutureOr<http.Response> Function(http.Request)> orderAnswers = [];

  /// When set, quotes wait for it.
  Completer<void>? holdQuote;

  /// When set, `POST /api/quote` answers with this status.
  int? quoteStatus;

  int orderNumber = 1001;

  List<http.Request> get quoteRequests =>
      requests.where((r) => r.url.path == '/api/quote').toList();
  List<http.Request> get orderRequests =>
      requests.where((r) => r.url.path == '/api/orders').toList();

  Map<String, dynamic> body(http.Request request) =>
      jsonDecode(request.body) as Map<String, dynamic>;

  OrderApi api() => OrderApi(
    base: 'https://orders.test',
    client: MockClient(_handle),
    sleep: (_) async {},
  );

  Variant? _variant(int id) {
    for (final p in _products) {
      final v = p.variantById(id);
      if (v != null) return v;
    }
    return null;
  }

  Product? _product(int id) {
    for (final p in _products) {
      if (p.variantById(id) != null) return p;
    }
    return null;
  }

  /// The quote for [request] (a quote or an order body).
  Map<String, dynamic> quoteFor(Map<String, dynamic> request) {
    final lines = <Map<String, dynamic>>[];
    final problems = <Map<String, dynamic>>[];
    var subtotal = 0;
    for (final line in (request['lines'] as List).cast<Map>()) {
      final id = line['variantId'] as int;
      final asked = line['quantity'] as int;
      final variant = _variant(id);
      final product = _product(id);
      final title = product?.title ?? 'Item';
      if (variant == null || soldOut.contains(id) || !variant.available) {
        lines.add({
          'variantId': id,
          'title': title,
          'variantTitle': variant?.title,
          'quantity': asked,
          'unitPriceFils': variant?.priceCents ?? 0,
          'lineTotalFils': 0,
          'available': false,
        });
        problems.add({
          'variantId': id,
          'kind': 'sold_out',
          'message': '$title is sold out.',
        });
        continue;
      }
      var quantity = asked;
      final left = stock[id];
      if (left != null && left < asked) {
        quantity = left;
        problems.add({
          'variantId': id,
          'kind': 'qty_reduced',
          'message': 'Only $left of $title left.',
        });
      }
      final price = prices[id] ?? variant.priceCents;
      final total = price * quantity;
      subtotal += total;
      lines.add({
        'variantId': id,
        'title': title,
        'variantTitle': variant.title == 'Default Title' ? null : variant.title,
        'quantity': quantity,
        'unitPriceFils': price,
        'lineTotalFils': total,
        'available': true,
      });
    }
    final express = (request['delivery'] as Map)['mode'] == 'express';
    final fee = subtotal == 0 || subtotal >= 20000 ? 0 : 2500;
    return {
      'lines': lines,
      'subtotalFils': subtotal,
      'deliveryFeeFils': fee,
      'totalFils': subtotal + fee,
      'currency': 'AED',
      'deliveryPromise': express ? '30–40 min' : 'Today within 6 hours',
      'problems': problems,
      'minOrderFils': 0,
    };
  }

  /// A 201 for [request] at its quoted total.
  http.Response created(http.Request request) {
    final quote = quoteFor(body(request));
    return http.Response(
      jsonEncode({
        'orderId': 'gid://shopify/Order/$orderNumber',
        'orderName': '#$orderNumber',
        'totalFils': quote['totalFils'],
        'deliveryPromise': quote['deliveryPromise'],
        'paymentMethod': 'Cash on Delivery',
      }),
      201,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  static http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    switch (request.url.path) {
      case '/api/health':
        return json(200, {'ok': true, 'version': '1.0.0'});
      case '/api/quote':
        await holdQuote?.future;
        final status = quoteStatus;
        if (status != null) return json(status, {'retryable': true});
        return json(200, quoteFor(body(request)));
      case '/api/orders':
        if (orderAnswers.isNotEmpty) {
          return await orderAnswers.removeAt(0)(request);
        }
        return created(request);
    }
    return json(404, {'error': 'not_found'});
  }
}

/// The Customer Account API in tests: [orders] as GraphQL answers, or
/// [status] / [errorCode] when set. Records the tokens it was sent.
class FakeCustomerApi {
  FakeCustomerApi({List<Map<String, dynamic>>? orders}) : orders = orders ?? [];

  List<Map<String, dynamic>> orders;

  /// While set, answers wait for it.
  Completer<void>? hold;
  int? status;
  String? errorCode;
  final List<String> tokens = [];

  /// Answers 401 to these tokens.
  final Set<String> rejected = {};

  Map<String, dynamic> customer = {
    'id': 'gid://shopify/Customer/1',
    'emailAddress': {'emailAddress': 'sara@example.com'},
    'phoneNumber': {'phoneNumber': '+971501234567'},
    'firstName': 'Sara',
    'lastName': 'Ahmed',
  };

  CustomerAccountApi api() => CustomerAccountApi(
    client: MockClient((request) async {
      final token = request.headers['authorization'] ?? '';
      tokens.add(token);
      await hold?.future;
      if (rejected.contains(token)) return http.Response('', 401);
      final code = status;
      if (code != null) return http.Response('', code);
      if (errorCode != null) {
        return FakeOrderServer.json(200, {
          'errors': [
            {
              'message': 'no',
              'extensions': {'code': errorCode},
            },
          ],
        });
      }
      final query = (jsonDecode(request.body) as Map)['query'] as String;
      if (query.contains('orders(')) {
        return FakeOrderServer.json(200, {
          'data': {
            'customer': {
              'orders': {'nodes': orders},
            },
          },
        });
      }
      return FakeOrderServer.json(200, {
        'data': {'customer': customer},
      });
    }),
  );
}

/// One order as the Customer Account API returns it.
Map<String, dynamic> orderJson({
  String name = '#1001',
  String processedAt = '2026-11-13T05:00:00Z',
  String amount = '147.5',
  String financialStatus = 'PENDING',
  String fulfillmentStatus = 'UNFULFILLED',
  String? cancelledAt,
  List<Map<String, dynamic>> fulfillments = const [],
  List<Map<String, dynamic>>? lines,
}) => {
  'id': 'gid://shopify/Order/${name.substring(1)}',
  'name': name,
  'processedAt': processedAt,
  'cancelledAt': cancelledAt,
  'financialStatus': financialStatus,
  'fulfillmentStatus': fulfillmentStatus,
  'totalPrice': {'amount': amount, 'currencyCode': 'AED'},
  'fulfillments': {'nodes': fulfillments},
  'lineItems': {
    'nodes':
        lines ??
        [
          {
            'title': 'Zespri Kiwi Sungold',
            'quantity': 2,
            'image': {'url': 'https://cdn.example.com/kiwi.jpg'},
            'variantId': 'gid://shopify/ProductVariant/2001',
          },
          {
            'title': 'Australian Beef Cubes',
            'quantity': 1,
            'image': null,
            'variantId': 'gid://shopify/ProductVariant/2003',
          },
        ],
    'pageInfo': {'hasNextPage': false},
  },
};
