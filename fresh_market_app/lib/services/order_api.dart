import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/store_config.dart';
import '../delivery/delivery_rules.dart';
import '../models/order.dart';

/// One line to quote or order.
class OrderLineRequest {
  const OrderLineRequest({required this.variantId, required this.quantity});

  final int variantId;
  final int quantity;

  Map<String, dynamic> toJson() => {
    'variantId': variantId,
    'quantity': quantity,
  };
}

/// How and where the order is delivered.
class DeliveryRequest {
  const DeliveryRequest({
    required this.mode,
    required this.area,
    this.promise,
    this.pin,
  });

  final DeliveryMode mode;
  final DeliveryArea area;

  /// The promise the shopper saw (the server works out its own).
  final String? promise;

  /// "lat,lng" of the building.
  final String? pin;

  Map<String, dynamic> toJson() => {
    'mode': mode.code,
    'area': {
      'name': area.name,
      'emirate': area.emirate.code,
      'lat': area.lat,
      'lng': area.lng,
    },
    if (promise != null && promise!.isNotEmpty) 'promise': promise,
    if (pin != null && pin!.isNotEmpty) 'pin': pin,
  };
}

/// The delivery address and the person the driver asks for.
class OrderAddress {
  const OrderAddress({
    required this.firstName,
    required this.lastName,
    required this.address1,
    required this.city,
    required this.emirate,
    required this.phone,
    this.address2 = '',
  });

  final String firstName;
  final String lastName;
  final String address1;
  final String address2;
  final String city;
  final Emirate emirate;

  /// Normalised, "+971501234567".
  final String phone;

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'address1': address1,
    if (address2.isNotEmpty) 'address2': address2,
    'city': city,
    'emirate': emirate.code,
    'phone': phone,
  };
}

/// The body of `POST /api/orders`.
class OrderRequest {
  const OrderRequest({
    required this.lines,
    required this.delivery,
    required this.address,
    this.instructions = '',
    this.expectedTotalFils,
  });

  final List<OrderLineRequest> lines;
  final DeliveryRequest delivery;
  final OrderAddress address;

  /// For the driver ("Call when you arrive").
  final String instructions;

  /// The total the shopper agreed to. The server answers 409 when its own
  /// total differs, so nobody is charged an amount they did not see.
  final int? expectedTotalFils;

  Map<String, dynamic> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
    'delivery': delivery.toJson(),
    'address': address.toJson(),
    if (instructions.isNotEmpty) 'instructions': instructions,
    'expectedTotalFils': ?expectedTotalFils,
  };
}

/// Why the order server could not do what was asked. [userMessage] is
/// short and plain, for the shopper.
sealed class OrderApiException implements Exception {
  const OrderApiException();

  String get userMessage;
}

/// The app was built without an order server (`ORDER_API_BASE`).
final class OrderingUnavailable extends OrderApiException {
  const OrderingUnavailable();

  @override
  String get userMessage => "Ordering isn't available in the app yet.";
}

/// No answer: offline, a timeout, or an answer that could not be read.
final class OrderNetworkError extends OrderApiException {
  const OrderNetworkError([this.cause]);

  final Object? cause;

  @override
  String get userMessage =>
      "We couldn't reach Fresh Market. Check your connection and try again.";
}

/// 401: the sign-in has expired or is not valid.
final class OrderUnauthorized extends OrderApiException {
  const OrderUnauthorized();

  @override
  String get userMessage => 'Please sign in again to place your order.';
}

/// 409: prices, stock or delivery changed. [quote] is the fresh quote
/// when the server sent one.
final class OrderChanged extends OrderApiException {
  const OrderChanged(this.problems, {this.quote});

  final List<QuoteProblem> problems;
  final Quote? quote;

  @override
  String get userMessage => 'Your order changed.';
}

/// 422: a field the server could not accept.
final class OrderInvalid extends OrderApiException {
  const OrderInvalid({required this.field, required this.message});

  /// "address.phone", "lines", ...
  final String field;
  final String message;

  @override
  String get userMessage =>
      message.isEmpty ? 'Something in your order needs a look.' : message;
}

/// 429: too many orders in a short time.
final class OrderRateLimited extends OrderApiException {
  const OrderRateLimited({this.retryAfter});

  final Duration? retryAfter;

  @override
  String get userMessage =>
      'You placed a lot of orders just now. Wait a little, then try again.';
}

/// 5xx (or another answer the app does not expect).
final class OrderServerError extends OrderApiException {
  const OrderServerError(this.statusCode, {this.retryable = false});

  final int statusCode;

  /// Trying again with the same Idempotency-Key may work.
  final bool retryable;

  @override
  String get userMessage =>
      "We couldn't place your order just now. Your cart is safe. "
      'Try again in a moment.';
}

/// The owner's order server (see `fresh_market_server/README.md`): quotes
/// a basket at the store's prices and places Cash on Delivery orders for a
/// signed-in customer.
class OrderApi {
  /// [base] is the server's address (`ORDER_API_BASE` by default); an
  /// empty or unusable one makes every call throw [OrderingUnavailable].
  /// [retryDelays] are the waits before each retry of an order; [sleep]
  /// waits (tests skip it).
  OrderApi({
    String base = StoreConfig.orderApiBase,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 3)],
    Future<void> Function(Duration)? sleep,
  }) : baseUri = _parseBase(base),
       _client = client ?? http.Client(),
       _sleep = sleep ?? Future<void>.delayed;

  final Uri? baseUri;
  final http.Client _client;
  final Duration timeout;

  /// How many times, and after how long, a failed order is sent again
  /// (with the same Idempotency-Key): at most two retries.
  final List<Duration> retryDelays;
  final Future<void> Function(Duration) _sleep;

  /// The app can order: it was built with an order server.
  bool get available => baseUri != null;

  static Uri? _parseBase(String base) {
    var text = base.trim();
    while (text.endsWith('/')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Uri _endpoint(String path) {
    final base = baseUri;
    if (base == null) throw const OrderingUnavailable();
    return base.replace(path: '${base.path}$path');
  }

  /// A new random (v4) UUID: one per checkout attempt, sent again on every
  /// retry of that attempt.
  static String newIdempotencyKey([Random? random]) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// `GET /api/health`: the server's version when it is up.
  Future<String> health() async {
    final response = await _send(() => _client.get(_endpoint('/api/health')));
    final body = _json(response);
    if (response.statusCode != 200 || body is! Map || body['ok'] != true) {
      throw OrderServerError(response.statusCode);
    }
    final version = body['version'];
    return version is String ? version : '';
  }

  /// `POST /api/quote`: the basket at the store's prices now, the delivery
  /// fee and promise, and anything that changed ([Quote.problems]).
  Future<Quote> quote({
    required List<OrderLineRequest> lines,
    required DeliveryRequest delivery,
  }) async {
    final body = jsonEncode({
      'lines': [for (final l in lines) l.toJson()],
      'delivery': {
        'mode': delivery.mode.code,
        'area': delivery.toJson()['area'],
      },
    });
    final response = await _send(
      () => _client.post(
        _endpoint('/api/quote'),
        headers: const {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: body,
      ),
    );
    if (response.statusCode == 200) {
      try {
        return Quote.fromJson(_json(response));
      } on FormatException catch (e) {
        throw OrderNetworkError(e);
      }
    }
    throw _error(response);
  }

  /// `POST /api/orders` for the customer signed in with [accessToken].
  ///
  /// No answer, or a 5xx the server says can be retried: sent again with
  /// the same [idempotencyKey] after each of [retryDelays] (the server
  /// never makes the order twice), then the last error is thrown.
  Future<PlacedOrder> placeOrder(
    OrderRequest order, {
    required String accessToken,
    required String idempotencyKey,
  }) async {
    final body = jsonEncode(order.toJson());
    for (var attempt = 0; ; attempt++) {
      try {
        return await _placeOnce(body, accessToken, idempotencyKey);
      } on OrderApiException catch (e) {
        final retry = switch (e) {
          OrderNetworkError() => true,
          OrderServerError(:final retryable) => retryable,
          _ => false,
        };
        if (!retry || attempt >= retryDelays.length) rethrow;
        await _sleep(retryDelays[attempt]);
      }
    }
  }

  Future<PlacedOrder> _placeOnce(
    String body,
    String accessToken,
    String idempotencyKey,
  ) async {
    final response = await _send(
      () => _client.post(
        _endpoint('/api/orders'),
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
          'authorization': 'Bearer $accessToken',
          'idempotency-key': idempotencyKey,
        },
        body: body,
      ),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      try {
        return PlacedOrder.fromJson(_json(response));
      } on FormatException catch (e) {
        // Made, but unreadable: the same key brings the same answer back.
        throw OrderNetworkError(e);
      }
    }
    throw _error(response);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on OrderApiException {
      rethrow;
    } on TimeoutException catch (e) {
      throw OrderNetworkError(e);
    } on http.ClientException catch (e) {
      throw OrderNetworkError(e);
    } catch (e) {
      // SocketException, HandshakeException (dart:io) and the like.
      throw OrderNetworkError(e);
    }
  }

  static Object? _json(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static OrderApiException _error(http.Response response) {
    final body = _json(response);
    final map = body is Map ? body : const {};
    final status = response.statusCode;
    switch (status) {
      case 401:
        return const OrderUnauthorized();
      case 409:
        Quote? quote;
        try {
          if (map['quote'] != null) quote = Quote.fromJson(map['quote']);
        } on FormatException {
          quote = null;
        }
        List<QuoteProblem> problems;
        try {
          problems = QuoteProblem.listFromJson(map['problems']);
        } on FormatException {
          problems = const [];
        }
        return OrderChanged(problems, quote: quote);
      case 422:
        final field = map['field'];
        final message = map['message'];
        return OrderInvalid(
          field: field is String ? field : '',
          message: message is String ? message : '',
        );
      case 429:
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ??
            (map['retryAfterSeconds'] is int
                ? map['retryAfterSeconds'] as int
                : null);
        return OrderRateLimited(
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
    }
    if (status >= 500) {
      // A 5xx without a body (a proxy, a crash) may be retried; the
      // server says false only when it is set up wrongly.
      return OrderServerError(status, retryable: map['retryable'] != false);
    }
    return OrderServerError(status);
  }
}
