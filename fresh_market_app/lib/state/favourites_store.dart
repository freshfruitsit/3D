import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../services/shopify_api.dart';

/// Favourite products, kept on the device as full products so the
/// favourites list can be drawn without the network.
class FavouritesStore extends ChangeNotifier {
  /// Reads saved favourites from [prefs]. With no [prefs] they live in
  /// memory only (tests).
  FavouritesStore({this._prefs}) {
    _restore();
  }

  static const String prefsKey = 'favourites_v1';

  final SharedPreferences? _prefs;

  /// Insertion-ordered by product id.
  final Map<int, Product> _products = {};

  /// Newest favourite first.
  List<Product> get products =>
      List.unmodifiable(_products.values.toList().reversed);

  int get count => _products.length;
  bool get isEmpty => _products.isEmpty;

  bool contains(int productId) => _products.containsKey(productId);

  /// Adds or removes [product]; returns true when it is now a favourite.
  bool toggle(Product product) {
    final nowFavourite = !_products.containsKey(product.id);
    if (nowFavourite) {
      _products[product.id] = product;
    } else {
      _products.remove(product.id);
    }
    _changed();
    return nowFavourite;
  }

  void remove(int productId) {
    if (_products.remove(productId) != null) _changed();
  }

  /// Reloads every favourite from the store so the list shows today's
  /// price and stock. A product the store no longer has is kept but shown
  /// as sold out; one that cannot be loaded right now is left as it is.
  Future<void> refresh(ShopifyApi api) async {
    final saved = _products.values.toList();
    if (saved.isEmpty) return;
    final fresh = <int, Product>{};
    await Future.wait(saved.map((old) async {
      if (old.handle.isEmpty) return;
      try {
        final product = await api.product(old.handle, refresh: true);
        // Keep the saved id as the key even if the handle was reused.
        if (product.id == old.id) fresh[old.id] = product;
      } on HttpStatusException catch (e) {
        if (e.isNotFound && old.available) fresh[old.id] = old.soldOut();
      } on ApiException {
        // Offline: keep the saved copy.
      }
    }));
    var changed = false;
    for (final entry in fresh.entries) {
      final current = _products[entry.key];
      // Skip favourites removed while loading.
      if (current == null) continue;
      if (jsonEncode(current.toJson()) != jsonEncode(entry.value.toJson())) {
        _products[entry.key] = entry.value; // keeps its place in the order
        changed = true;
      }
    }
    if (changed) _changed();
  }

  void _changed() {
    notifyListeners();
    _prefs?.setString(
      prefsKey,
      jsonEncode([for (final p in _products.values) p.toJson()]),
    );
  }

  void _restore() {
    final raw = _prefs?.getString(prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      for (final item in jsonDecode(raw) as List) {
        final product = Product.fromJson(item as Map<String, dynamic>);
        _products[product.id] = product;
      }
    } catch (_) {
      _products.clear();
    }
  }
}
