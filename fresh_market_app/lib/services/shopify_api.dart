import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/collection.dart';
import '../models/product.dart';

/// Base of every error the store API can raise. Screens can show
/// [userMessage] next to a retry button.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  /// Technical detail for logs.
  final String message;

  /// Short text that is safe to show to a shopper.
  String get userMessage;

  @override
  String toString() => '$runtimeType: $message';
}

/// No connection, DNS failure or timeout.
final class NetworkException extends ApiException {
  const NetworkException(super.message);

  @override
  String get userMessage =>
      'We could not reach the store. Check your connection and try again.';
}

/// The store answered with a non-success status.
final class HttpStatusException extends ApiException {
  const HttpStatusException(this.statusCode, super.message);

  final int statusCode;

  bool get isNotFound => statusCode == 404;

  @override
  String get userMessage => isNotFound
      ? 'This item is no longer available.'
      : 'The store is not responding right now. Please try again.';
}

/// The store answered with something we could not read.
final class ParseException extends ApiException {
  const ParseException(super.message);

  @override
  String get userMessage =>
      'Something went wrong loading this. Please try again.';
}

/// Read-only access to the public storefront.
abstract interface class ShopifyApi {
  /// Default page size of [collectionProducts].
  static const int pageSize = 24;

  /// One page of a collection's products. Pages start at 1. A page with
  /// fewer than [limit] products is the last one. An unknown handle throws
  /// [HttpStatusException] with `isNotFound`.
  Future<List<Product>> collectionProducts(
    String handle, {
    int page = 1,
    int limit = pageSize,
  });

  /// Every collection of the store.
  Future<List<Collection>> collections();

  /// Products matching [query], best match first, as full products (with
  /// variants). An empty query gives an empty list.
  Future<List<Product>> search(String query, {int limit = 10});

  /// One full product by handle. With [refresh] it is always loaded from
  /// the store, never from a cache.
  Future<Product> product(String handle, {bool refresh = false});
}

/// Loads a collection in one go, for a price sort or the deals.
extension WholeCollection on ShopifyApi {
  /// Page size used to fetch a whole collection.
  static const int bulkLimit = 250;

  /// Safety cap on bulk pages (2,000 products).
  static const int bulkMaxPages = 8;

  /// Every product of [handle] in the store's order, loaded in pages of
  /// [bulkLimit]; past [bulkMaxPages] pages the rest is left out.
  Future<List<Product>> wholeCollection(String handle) async {
    final all = <Product>[];
    final ids = <int>{};
    for (var page = 1; page <= bulkMaxPages; page++) {
      final batch = await collectionProducts(
        handle,
        page: page,
        limit: bulkLimit,
      );
      for (final p in batch) {
        if (ids.add(p.id)) all.add(p);
      }
      if (batch.length < bulkLimit) break;
    }
    return all;
  }
}

/// [ShopifyApi] over the public storefront JSON endpoints.
class HttpShopifyApi implements ShopifyApi {
  HttpShopifyApi({
    http.Client? client,
    this.host = 'testtfm.myshopify.com',
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String host;
  final Duration timeout;

  /// Full products already loaded, by handle. Keeps search fast, because a
  /// search result has to be loaded as a full product before it can be
  /// added to the cart.
  ///
  /// Entries older than [productCacheTtl] are loaded again, so prices and
  /// stock do not go stale while the app stays open. Oldest entry first.
  final Map<String, ({Product product, DateTime loadedAt})> _productCache = {};

  /// How long a cached product is trusted.
  static const Duration productCacheTtl = Duration(minutes: 5);

  /// The most products kept in the cache.
  static const int productCacheSize = 200;

  /// The clock of the cache (replaceable in tests).
  DateTime Function() now = DateTime.now;

  void _remember(Product product, [String? handle]) {
    final key = handle ?? product.handle;
    if (key.isEmpty) return;
    _productCache
      ..remove(key)
      ..[key] = (product: product, loadedAt: now());
    while (_productCache.length > productCacheSize) {
      _productCache.remove(_productCache.keys.first);
    }
  }

  @override
  Future<List<Product>> collectionProducts(
    String handle, {
    int page = 1,
    int limit = ShopifyApi.pageSize,
  }) async {
    final json = await _getJson('/collections/$handle/products.json', {
      'limit': '$limit',
      'page': '$page',
    });
    final products = _parse(() => Product.listFromJson(_asMap(json)));
    // So search and cart rows agree with the list just shown.
    products.forEach(_remember);
    return products;
  }

  @override
  Future<List<Collection>> collections() async {
    final json = await _getJson('/collections.json', {'limit': '250'});
    return _parse(
      () => [
        for (final c in (_asMap(json)['collections'] as List? ?? const []))
          if (c is Map<String, dynamic>) Collection.fromJson(c),
      ],
    );
  }

  @override
  Future<List<Product>> search(String query, {int limit = 10}) async {
    final term = query.trim();
    if (term.isEmpty) return const [];
    final json = await _getJson('/search/suggest.json', {
      'q': term,
      'resources[type]': 'product',
      'resources[limit]': '$limit',
    });
    final handles = _parse(() {
      final resources = _asMap(json)['resources'];
      final results = resources is Map ? resources['results'] : null;
      final products = results is Map ? results['products'] : null;
      return <String>[
        for (final p in (products as List? ?? const []))
          if (p is Map && p['handle'] is String) p['handle'] as String,
      ];
    });
    if (handles.isEmpty) return const [];

    // Suggest results carry no variants, so load each one in full. A result
    // that fails to load is dropped; if every one fails, report the error.
    ApiException? lastError;
    final loaded = await Future.wait(
      handles.map((handle) async {
        try {
          return await product(handle);
        } on ApiException catch (e) {
          lastError = e;
          return null;
        }
      }),
    );
    final found = loaded.whereType<Product>().toList();
    if (found.isEmpty && lastError != null) throw lastError!;
    return found;
  }

  @override
  Future<Product> product(String handle, {bool refresh = false}) async {
    final cached = _productCache[handle];
    if (!refresh &&
        cached != null &&
        now().difference(cached.loadedAt) < productCacheTtl) {
      return cached.product;
    }
    // The .js shape is used because it carries `available` per variant.
    final json = await _getJson('/products/$handle.js', const {});
    final product = _parse(() => Product.fromJson(_asMap(json)));
    _remember(product, handle);
    return product;
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();

  Future<Object?> _getJson(String path, Map<String, String> query) async {
    final uri = Uri.https(host, path, query.isEmpty ? null : query);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw NetworkException('Timed out after ${timeout.inSeconds}s: $uri');
    } on SocketException catch (e) {
      throw NetworkException('${e.message}: $uri');
    } on http.ClientException catch (e) {
      throw NetworkException('${e.message}: $uri');
    } on HandshakeException catch (e) {
      throw NetworkException('${e.message}: $uri');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpStatusException(
        response.statusCode,
        'HTTP ${response.statusCode}: $uri',
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw ParseException('${e.message}: $uri');
    }
  }

  static Map<String, dynamic> _asMap(Object? json) {
    if (json is Map<String, dynamic>) return json;
    throw const ParseException('Expected a JSON object');
  }

  static T _parse<T>(T Function() read) {
    try {
      return read();
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ParseException('$e');
    }
  }
}
