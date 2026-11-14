import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/store_config.dart';
import '../models/order.dart';

/// The signed-in customer, from the Customer Account API.
@immutable
class CustomerProfile {
  const CustomerProfile({
    this.email,
    this.phone,
    this.firstName = '',
    this.lastName = '',
  });

  final String? email;
  final String? phone;
  final String firstName;
  final String lastName;
}

/// Why the Customer Account API did not answer.
sealed class CustomerApiException implements Exception {
  const CustomerApiException();

  String get userMessage;
}

/// 401: the access token is not (or no longer) valid.
final class CustomerApiUnauthorized extends CustomerApiException {
  const CustomerApiUnauthorized();

  @override
  String get userMessage => 'Please sign in again to see your orders.';
}

/// Offline, a timeout, or an answer that could not be read.
final class CustomerApiNetworkError extends CustomerApiException {
  const CustomerApiNetworkError([this.cause]);

  final Object? cause;

  @override
  String get userMessage =>
      "We couldn't load your orders. Check your connection and try again.";
}

/// Any other error (throttled, a GraphQL error, a 5xx).
final class CustomerApiError extends CustomerApiException {
  const CustomerApiError(this.detail);

  final String detail;

  @override
  String get userMessage =>
      "We couldn't load your orders just now. Try again in a moment.";
}

/// Shopify's Customer Account API (GraphQL, version
/// [CustomerAccountConfig.apiVersion]) for the signed-in customer. Every
/// field below was checked against https://shopify.dev/docs/api/customer/2026-10.
class CustomerAccountApi {
  CustomerAccountApi({
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       endpoint = endpoint ?? Uri.parse(CustomerAccountConfig.graphqlEndpoint);

  final http.Client _client;
  final Uri endpoint;
  final Duration timeout;

  static const String customerQuery = '''
query Customer {
  customer {
    id
    emailAddress { emailAddress }
    phoneNumber { phoneNumber }
    firstName
    lastName
  }
}''';

  /// The 20 latest orders, newest first, each with its first 20 lines.
  static const String ordersQuery = '''
query Orders {
  customer {
    orders(first: 20, sortKey: PROCESSED_AT, reverse: true) {
      nodes {
        id
        name
        processedAt
        cancelledAt
        financialStatus
        fulfillmentStatus
        totalPrice { amount currencyCode }
        fulfillments(first: 1, sortKey: CREATED_AT, reverse: true) {
          nodes { status latestShipmentStatus }
        }
        lineItems(first: 20) {
          nodes { title name quantity image { url } variantId }
          pageInfo { hasNextPage }
        }
      }
    }
  }
}''';

  Future<CustomerProfile> customer(String accessToken) async {
    final data = await _query(accessToken, 'Customer', customerQuery);
    final customer = data['customer'];
    if (customer is! Map) throw const CustomerApiError('no customer');
    String? inner(Object? map, String key) {
      if (map is! Map) return null;
      final value = map[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    String text(String key) {
      final value = customer[key];
      return value is String ? value.trim() : '';
    }

    return CustomerProfile(
      email: inner(customer['emailAddress'], 'emailAddress'),
      phone: inner(customer['phoneNumber'], 'phoneNumber'),
      firstName: text('firstName'),
      lastName: text('lastName'),
    );
  }

  Future<List<CustomerOrder>> orders(String accessToken) async {
    final data = await _query(accessToken, 'Orders', ordersQuery);
    final customer = data['customer'];
    final orders = customer is Map ? customer['orders'] : null;
    final nodes = orders is Map ? orders['nodes'] : null;
    if (nodes is! List) throw const CustomerApiError('no orders');
    try {
      return [for (final node in nodes) CustomerOrder.fromJson(node)];
    } on FormatException catch (e) {
      throw CustomerApiNetworkError(e);
    }
  }

  Future<Map<dynamic, dynamic>> _query(
    String accessToken,
    String operationName,
    String query,
  ) async {
    http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              // The raw token: the Customer Account API takes no "Bearer".
              'authorization': accessToken,
            },
            body: jsonEncode({
              'operationName': operationName,
              'query': query,
              'variables': const <String, Object?>{},
            }),
          )
          .timeout(timeout);
    } catch (e) {
      throw CustomerApiNetworkError(e);
    }
    if (response.statusCode == 401) throw const CustomerApiUnauthorized();
    if (response.statusCode != 200) {
      throw CustomerApiError('HTTP ${response.statusCode}');
    }
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (e) {
      throw CustomerApiNetworkError(e);
    }
    if (body is! Map) throw const CustomerApiError('not JSON');
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final code = first is Map && first['extensions'] is Map
          ? (first['extensions'] as Map)['code']
          : null;
      // Bad credentials are an HTTP 401 (above). ACCESS_DENIED is a
      // permission the app lacks (protected customer data, a scope), which
      // signing in again does not fix: an error, not "sign in again".
      if (code == 'UNAUTHENTICATED') throw const CustomerApiUnauthorized();
      throw CustomerApiError('$code');
    }
    final data = body['data'];
    if (data is! Map) throw const CustomerApiError('no data');
    return data;
  }
}
