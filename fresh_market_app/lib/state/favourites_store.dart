import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';

/// Favourite products, kept on the device as full products so the
/// favourites list can be drawn without the network.
class FavouritesStore extends ChangeNotifier {
  /// Reads saved favourites from [prefs]. With no [prefs] they live in
  /// memory only (tests).
  FavouritesStore({SharedPreferences? this._prefs}) {
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
