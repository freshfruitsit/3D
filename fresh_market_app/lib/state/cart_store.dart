import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../delivery/delivery_rules.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';

/// One line of the cart. Holds everything needed to draw the row without
/// the network.
@immutable
class CartLine {
  const CartLine({
    required this.variantId,
    required this.productId,
    required this.handle,
    required this.title,
    required this.priceCents,
    required this.quantity,
    this.variantTitle,
    this.compareAtCents,
    this.imageUrl,
    this.origin,
    this.express,
    this.size,
    this.available = true,
  });

  factory CartLine.of(Product product, Variant variant, int quantity) =>
      CartLine(
        variantId: variant.id,
        productId: product.id,
        handle: product.handle,
        title: product.title,
        variantTitle: variant.label,
        priceCents: variant.priceCents,
        compareAtCents: variant.oldPriceCents,
        imageUrl: product.imageUrl,
        origin: product.origin,
        express: DeliveryRules.isExpressEligible(product),
        size: product.sizeText(variant),
        available: variant.available,
        quantity: quantity,
      );

  final int variantId;
  final int productId;

  /// Product handle, to reload the full product (`api.product(handle)`).
  final String handle;
  final String title;

  /// "500 GM", or null for a product without options.
  final String? variantTitle;

  /// Unit price in minor units.
  final int priceCents;

  /// Old unit price; set only when the variant is on sale.
  final int? compareAtCents;
  final String? imageUrl;
  final String? origin;

  /// True when the product can come by Express (tagged "1hr-delivery");
  /// null for a line saved before the app knew, until the cart is checked
  /// against the store again.
  final bool? express;

  /// The size as shown ("500 g", "1 kg"): the variant's, or one the store
  /// wrote in the product's title or description. Null when there is none.
  final String? size;

  /// False once the store says this variant is sold out (it is still
  /// listed). Such a line is left out of the subtotal and of checkout.
  final bool available;
  final int quantity;

  /// [size], or for a line saved before the app kept it, the variant's
  /// title written the shop-floor way.
  String? get sizeLabel => size ?? formatSize(variantTitle);

  bool get onSale => compareAtCents != null && compareAtCents! > priceCents;

  int get lineTotalCents => priceCents * quantity;

  /// The line total at the old price, to strike through; null when not on
  /// sale.
  int? get oldLineTotalCents => onSale ? compareAtCents! * quantity : null;

  /// The size, and the unit price once there is more than one: "500 g",
  /// "500 g · \u20C3 4.75 each", "\u20C3 300.00 each" (the Dirham sign, see
  /// formatMoney). At one unit the line total already says the price.
  String get detailLine => [
        ?sizeLabel,
        if (quantity > 1) '${formatMoney(priceCents)} each',
      ].join(' · ');

  /// What screen readers hear for [detailLine] ("500 g, AED 4.75 each").
  String get detailSemantics => [
        ?sizeLabel,
        if (quantity > 1) '${moneySemantics(priceCents)} each',
      ].join(', ');

  CartLine withQuantity(int quantity) => CartLine(
        variantId: variantId,
        productId: productId,
        handle: handle,
        title: title,
        variantTitle: variantTitle,
        priceCents: priceCents,
        compareAtCents: compareAtCents,
        imageUrl: imageUrl,
        origin: origin,
        express: express,
        size: size,
        available: available,
        quantity: quantity,
      );

  factory CartLine.fromJson(Map<String, dynamic> json) => CartLine(
        variantId: (json['variantId'] as num).toInt(),
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        handle: (json['handle'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        variantTitle: json['variantTitle'] as String?,
        priceCents: (json['priceCents'] as num?)?.toInt() ?? 0,
        compareAtCents: (json['compareAtCents'] as num?)?.toInt(),
        imageUrl: json['imageUrl'] as String?,
        origin: json['origin'] as String?,
        express: json['express'] as bool?,
        size: json['size'] as String?,
        available: json['available'] as bool? ?? true,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'variantId': variantId,
        'productId': productId,
        'handle': handle,
        'title': title,
        'variantTitle': variantTitle,
        'priceCents': priceCents,
        'compareAtCents': compareAtCents,
        'imageUrl': imageUrl,
        'origin': origin,
        'express': express,
        'size': size,
        'available': available,
        'quantity': quantity,
      };
}

/// The shopping cart: lines keyed by variant id, kept on the device.
class CartStore extends ChangeNotifier {
  /// Reads any saved cart from [prefs]. With no [prefs] the cart lives in
  /// memory only (tests).
  CartStore({this._prefs}) {
    _restore();
  }

  static const String prefsKey = 'cart_v1';
  static const String storeHost = 'testtfm.myshopify.com';

  /// The most of one variant a cart line can hold.
  static const int maxQuantity = 99;

  final SharedPreferences? _prefs;

  /// Insertion-ordered: the first product added stays on top.
  final Map<int, CartLine> _lines = {};

  List<CartLine> get lines => List.unmodifiable(_lines.values);

  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;

  /// Total units across all lines (the badge count).
  int get itemCount =>
      _lines.values.fold(0, (sum, line) => sum + line.quantity);

  /// The total of the lines that can be bought: a line the store has
  /// marked sold out since it was added is not counted.
  int get subtotalCents => _lines.values
      .where((line) => line.available)
      .fold(0, (sum, line) => sum + line.lineTotalCents);

  /// Lines the store has marked sold out since they were added.
  int get soldOutLines => _lines.values.where((l) => !l.available).length;

  /// True when at least one line can be checked out.
  bool get hasAvailableLines => _lines.values.any((l) => l.available);

  /// Units of one variant in the cart (0 when absent).
  int quantityOf(int variantId) => _lines[variantId]?.quantity ?? 0;

  /// Units of a product in the cart across all its variants.
  int quantityOfProduct(int productId) => _lines.values
      .where((line) => line.productId == productId)
      .fold(0, (sum, line) => sum + line.quantity);

  CartLine? lineOf(int variantId) => _lines[variantId];

  /// Adds [quantity] units of [variant], refreshing the saved name, price
  /// and photo. Sold-out variants are ignored.
  void add(Product product, Variant variant, {int quantity = 1}) {
    if (quantity <= 0 || !variant.available) return;
    final next = (quantityOf(variant.id) + quantity).clamp(1, maxQuantity);
    _lines[variant.id] = CartLine.of(product, variant, next);
    _changed();
  }

  /// One more unit of a line already in the cart.
  void increment(int variantId) =>
      setQuantity(variantId, quantityOf(variantId) + 1);

  /// One unit fewer; reaching 0 removes the line.
  void decrement(int variantId) =>
      setQuantity(variantId, quantityOf(variantId) - 1);

  /// Sets the units of a line already in the cart; 0 or less removes it.
  void setQuantity(int variantId, int quantity) {
    final line = _lines[variantId];
    if (line == null) return;
    if (quantity <= 0) {
      _lines.remove(variantId);
    } else {
      final next = quantity > maxQuantity ? maxQuantity : quantity;
      if (next == line.quantity) return;
      _lines[variantId] = line.withQuantity(next);
    }
    _changed();
  }

  void remove(int variantId) {
    if (_lines.remove(variantId) != null) _changed();
  }

  /// Puts back a [line] that was just removed ("Undo"), at [index] in the
  /// cart's order (the end when out of range). Does nothing when the
  /// variant is back in the cart already.
  void restoreLine(CartLine line, {int? index}) {
    if (_lines.containsKey(line.variantId) || line.quantity <= 0) return;
    final entries = _lines.entries.toList();
    final at = index == null || index < 0 || index > entries.length
        ? entries.length
        : index;
    entries.insert(at, MapEntry(line.variantId, line));
    _lines
      ..clear()
      ..addEntries(entries);
    _changed();
  }

  /// Where the line of [variantId] sits in the cart's order, or -1.
  int indexOf(int variantId) => _lines.keys.toList().indexOf(variantId);

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    _changed();
  }

  /// Checks every line against the store: a line whose product or variant
  /// no longer exists is removed (Shopify refuses a checkout containing
  /// one), the others get today's name, price, photo and availability (a
  /// sold-out variant stays listed, marked [CartLine.available] false, and
  /// is left out of the subtotal and of checkout). A product that cannot
  /// be loaded right now (offline) is left as it is.
  ///
  /// Returns how many lines were removed.
  Future<int> revalidate(ShopifyApi api) async {
    final handles = {
      for (final line in _lines.values)
        if (line.handle.isNotEmpty) line.handle,
    };
    if (handles.isEmpty) return 0;

    // handle -> fresh product, or null when the store no longer has it.
    final fresh = <String, Product?>{};
    await Future.wait(handles.map((handle) async {
      try {
        fresh[handle] = await api.product(handle, refresh: true);
      } on HttpStatusException catch (e) {
        if (e.isNotFound) fresh[handle] = null;
      } on ApiException {
        // Unknown for now; keep the line.
      }
    }));

    var removed = 0;
    var changed = false;
    // Lines as they are now: the shopper may have edited the cart while
    // the products were loading.
    for (final line in _lines.values.toList()) {
      if (!fresh.containsKey(line.handle)) continue;
      final product = fresh[line.handle];
      final variant = product?.variantById(line.variantId);
      if (product == null || variant == null) {
        _lines.remove(line.variantId);
        removed++;
        changed = true;
        continue;
      }
      final next = CartLine.of(product, variant, line.quantity);
      if (!mapEquals(next.toJson(), line.toJson())) {
        _lines[line.variantId] = next;
        changed = true;
      }
    }
    if (changed) _changed();
    return removed;
  }

  /// The Shopify cart permalink that opens checkout with this cart, or
  /// null when the cart is empty.
  Uri? get checkoutUrl => checkoutUrlWith(const {});

  /// [checkoutUrl] carrying the order's cart [attributes] (the website's
  /// "Delivery mode", "Delivery area", ...) and the checkout fields to
  /// fill in ([prefill], see `CheckoutPrefill.params`).
  /// Sold-out lines are left out.
  Uri? checkoutUrlWith(
    Map<String, String> attributes, {
    Map<String, String> prefill = const {},
  }) => buildCheckoutUrl(
        {
          for (final line in _lines.values)
            if (line.available) line.variantId: line.quantity,
        },
        attributes: attributes,
        prefill: prefill,
      );

  /// Units of Express items ([CartLine.express]) and of the others; a line
  /// not checked yet counts as neither.
  ({int express, int other}) get expressSplit {
    var express = 0;
    var other = 0;
    for (final line in _lines.values) {
      if (line.express == true) express += line.quantity;
      if (line.express == false) other += line.quantity;
    }
    return (express: express, other: other);
  }

  /// `https://testtfm.myshopify.com/cart/{variantId}:{qty},{variantId}:{qty}`,
  /// followed by `?attributes[Name]=value&...` for each of [attributes]
  /// (percent-encoded; Shopify cart permalinks copy them onto the cart),
  /// then `&key=value` for each of [prefill] (checkout fields such as
  /// `checkout[email]`, percent-encoded the same way; empty values are
  /// left out).
  /// Entries with a quantity of 0 or less are left out; null when nothing
  /// remains.
  static Uri? buildCheckoutUrl(
    Map<int, int> quantitiesByVariantId, {
    Map<String, String> attributes = const {},
    Map<String, String> prefill = const {},
  }) {
    final parts = [
      for (final entry in quantitiesByVariantId.entries)
        if (entry.value > 0) '${entry.key}:${entry.value}',
    ];
    if (parts.isEmpty) return null;
    final query = [
      for (final entry in attributes.entries)
        '${Uri.encodeComponent('attributes[${entry.key}]')}='
            '${Uri.encodeComponent(entry.value)}',
      for (final entry in prefill.entries)
        if (entry.value.trim().isNotEmpty)
          '${Uri.encodeComponent(entry.key)}='
              '${Uri.encodeComponent(entry.value)}',
    ].join('&');
    return Uri.parse(
      'https://$storeHost/cart/${parts.join(',')}'
      '${query.isEmpty ? '' : '?$query'}',
    );
  }

  void _changed() {
    notifyListeners();
    _prefs?.setString(
      prefsKey,
      jsonEncode([for (final line in _lines.values) line.toJson()]),
    );
  }

  void _restore() {
    final raw = _prefs?.getString(prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      for (final item in jsonDecode(raw) as List) {
        final line = CartLine.fromJson(item as Map<String, dynamic>);
        if (line.quantity > 0) _lines[line.variantId] = line;
      }
    } catch (_) {
      // A saved cart we cannot read is dropped rather than crashing.
      _lines.clear();
    }
  }
}
