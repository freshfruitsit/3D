import 'money.dart';

/// One purchasable variant of a product. Prices are in minor units (fils).
class Variant {
  const Variant({
    required this.id,
    required this.title,
    required this.priceCents,
    this.compareAtCents,
    this.available = true,
  });

  static const String defaultTitle = 'Default Title';

  final int id;
  final String title;
  final int priceCents;

  /// The old price, only when the store set one.
  final int? compareAtCents;
  final bool available;

  /// True for the single placeholder variant of a product without options.
  bool get isDefault => title == defaultTitle;

  /// The variant title for display ("500 GM"), or null for the placeholder.
  String? get label => isDefault || title.isEmpty ? null : title;

  /// True only when the old price is higher than the price.
  bool get onSale => compareAtCents != null && compareAtCents! > priceCents;

  /// The old price to strike through, or null when not on sale.
  int? get oldPriceCents => onSale ? compareAtCents : null;

  /// Whole-number discount (46 for "-46%"), or null when not on sale.
  int? get salePercent {
    if (!onSale) return null;
    final percent =
        ((compareAtCents! - priceCents) * 100 / compareAtCents!).round();
    return percent < 1 ? null : percent;
  }

  String get priceText => formatMoney(priceCents);

  factory Variant.fromJson(Map<String, dynamic> json) => Variant(
        id: (json['id'] as num).toInt(),
        title: (json['title'] as String?) ?? defaultTitle,
        priceCents: parseMoney(json['price']) ?? 0,
        compareAtCents: parseMoney(json['compare_at_price']),
        available: json['available'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'price': moneyToDecimalString(priceCents),
        'compare_at_price': compareAtCents == null
            ? null
            : moneyToDecimalString(compareAtCents!),
        'available': available,
      };
}

/// A product option such as "Weight" with its values.
class ProductOption {
  const ProductOption({required this.name, required this.values});

  final String name;
  final List<String> values;

  factory ProductOption.fromJson(Map<String, dynamic> json) => ProductOption(
        name: (json['name'] as String?) ?? '',
        values: [
          for (final v in (json['values'] as List? ?? const []))
            if (v is String) v,
        ],
      );

  Map<String, dynamic> toJson() => {'name': name, 'values': values};
}

/// A small fact shown as a chip on product detail, derived from tags.
enum ProductFact {
  express('1Hr Express'),
  local('Local UAE'),
  byAir('By air');

  const ProductFact(this.label);
  final String label;
}

/// A store product. Parses every public storefront shape:
/// `/collections/x/products.json`, `/products/x.js` and `/products/x.json`.
class Product {
  const Product({
    required this.id,
    required this.title,
    required this.handle,
    this.descriptionHtml = '',
    this.vendor = '',
    this.productType = '',
    this.tags = const [],
    this.variants = const [],
    this.images = const [],
    this.options = const [],
  });

  final int id;
  final String title;
  final String handle;
  final String descriptionHtml;
  final String vendor;
  final String productType;
  final List<String> tags;
  final List<Variant> variants;

  /// Full-size image URLs (https). Resize with [shopifyImageUrl].
  final List<String> images;
  final List<ProductOption> options;

  // ---- variants ----------------------------------------------------------

  /// True when at least one variant can be bought.
  bool get available => variants.any((v) => v.available);

  /// The variant to show and add by default: the first one in stock,
  /// otherwise the first one. Null only for a product without variants.
  Variant? get defaultVariant {
    if (variants.isEmpty) return null;
    for (final v in variants) {
      if (v.available) return v;
    }
    return variants.first;
  }

  /// True when the shopper has a real choice of variants.
  bool get hasVariantChoice =>
      variants.length > 1 || (variants.isNotEmpty && !variants.first.isDefault);

  /// Heading for the variant buttons: the option name ("Weight"), or
  /// "Options" when the store gave none.
  String get optionName {
    if (options.isNotEmpty) {
      final name = options.first.name;
      if (name.isNotEmpty && name != 'Title') return name;
    }
    return 'Options';
  }

  Variant? variantById(int id) {
    for (final v in variants) {
      if (v.id == id) return v;
    }
    return null;
  }

  // ---- images ------------------------------------------------------------

  String? get imageUrl => images.isEmpty ? null : images.first;

  // ---- facts from tags ---------------------------------------------------

  bool _hasTag(String tag) {
    final wanted = tag.toLowerCase();
    return tags.any((t) => t.toLowerCase() == wanted);
  }

  /// Country or source from the `origin:` tag ("Peru"); "UAE" for local
  /// products without one; otherwise null.
  String? get origin {
    for (final tag in tags) {
      if (tag.toLowerCase().startsWith('origin:')) {
        final value = tag.substring('origin:'.length).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return isLocal ? 'UAE' : null;
  }

  bool get isExpress => _hasTag('1hr-delivery');
  bool get isLocal => _hasTag('UAE') || _hasTag('Local');
  bool get isByAir => _hasTag('AIR') || _hasTag('By air');

  /// Fact chips for product detail, in display order.
  List<ProductFact> get facts => [
        if (isExpress) ProductFact.express,
        if (isLocal) ProductFact.local,
        if (isByAir) ProductFact.byAir,
      ];

  /// The 12px secondary line under a product name: origin and variant
  /// title joined with " · " ("UAE · 500 GM"). Empty when neither exists.
  String sizeLine([Variant? variant]) {
    final v = variant ?? defaultVariant;
    return [
      if (origin != null) origin!,
      if (v?.label != null) v!.label!,
    ].join(' · ');
  }

  /// The description as plain text with the HTML removed.
  String get description => stripHtml(descriptionHtml);

  // ---- JSON --------------------------------------------------------------

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final tags = <String>[
      if (rawTags is List)
        for (final t in rawTags)
          if (t is String) t
      else if (rawTags is String)
        for (final t in rawTags.split(','))
          if (t.trim().isNotEmpty) t.trim(),
    ];

    final images = <String>[];
    for (final image in (json['images'] as List? ?? const [])) {
      final src = image is String
          ? image
          : image is Map
              ? image['src']
              : null;
      if (src is String && src.isNotEmpty) images.add(_absoluteUrl(src));
    }
    if (images.isEmpty) {
      final single = json['featured_image'] ?? json['image'];
      final src = single is String
          ? single
          : single is Map
              ? (single['src'] ?? single['url'])
              : null;
      if (src is String && src.isNotEmpty) images.add(_absoluteUrl(src));
    }

    return Product(
      id: (json['id'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      handle: (json['handle'] as String?) ?? '',
      descriptionHtml: (json['body_html'] ??
              json['description'] ??
              json['body'] ??
              '') as String,
      vendor: (json['vendor'] as String?) ?? '',
      productType:
          (json['product_type'] ?? json['type'] ?? '') as String,
      tags: tags,
      variants: [
        for (final v in (json['variants'] as List? ?? const []))
          if (v is Map<String, dynamic>) Variant.fromJson(v),
      ],
      images: images,
      options: [
        for (final o in (json['options'] as List? ?? const []))
          if (o is Map<String, dynamic>) ProductOption.fromJson(o),
      ],
    );
  }

  /// Serialises in the `products.json` shape, so [Product.fromJson] reads it
  /// back. Used to keep favourites on the device.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'handle': handle,
        'body_html': descriptionHtml,
        'vendor': vendor,
        'product_type': productType,
        'tags': tags,
        'variants': [for (final v in variants) v.toJson()],
        'images': [
          for (final src in images) {'src': src},
        ],
        'options': [for (final o in options) o.toJson()],
      };

  /// Parses the `{products:[...]}` body of a collection page.
  static List<Product> listFromJson(Map<String, dynamic> json) => [
        for (final p in (json['products'] as List? ?? const []))
          if (p is Map<String, dynamic>) Product.fromJson(p),
      ];
}

String _absoluteUrl(String src) => src.startsWith('//') ? 'https:$src' : src;

/// Adds Shopify's resize parameter to a CDN image URL. [width] is in
/// physical pixels.
String shopifyImageUrl(String url, {int? width}) {
  if (width == null || url.isEmpty) return url;
  final uri = Uri.tryParse(_absoluteUrl(url));
  if (uri == null) return url;
  return uri.replace(
    queryParameters: {...uri.queryParameters, 'width': '$width'},
  ).toString();
}

/// Turns product description HTML into readable plain text: block tags
/// become line breaks, list items get a bullet, entities are decoded.
String stripHtml(String html) {
  if (html.isEmpty) return '';
  var text = html.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  text = text.replaceAll(RegExp(r'<\s*br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<\s*li[^>]*>', caseSensitive: false), '\n• ');
  text = text.replaceAll(
    RegExp(r'<\s*/\s*(p|div|h[1-6]|ul|ol|tr|table)\s*>', caseSensitive: false),
    '\n\n',
  );
  text = text.replaceAll(RegExp(r'<[^>]*>'), '');
  text = _decodeEntities(text);
  final lines = text.split('\n').map((l) {
    return l.replaceAll(RegExp(r'[  ]+'), ' ').trim();
  }).toList();
  final out = <String>[];
  for (final line in lines) {
    if (line == '•') continue;
    if (line.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

const Map<String, String> _entities = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ndash': '–',
  'mdash': '—',
  'rsquo': '’',
  'lsquo': '‘',
  'rdquo': '”',
  'ldquo': '“',
  'trade': '™',
  'reg': '®',
  'deg': '°',
  'hellip': '…',
};

String _decodeEntities(String text) => text.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'),
      (m) {
        final body = m.group(1)!;
        if (body.startsWith('#x') || body.startsWith('#X')) {
          final code = int.tryParse(body.substring(2), radix: 16);
          return code == null ? m.group(0)! : String.fromCharCode(code);
        }
        if (body.startsWith('#')) {
          final code = int.tryParse(body.substring(1));
          return code == null ? m.group(0)! : String.fromCharCode(code);
        }
        return _entities[body] ?? m.group(0)!;
      },
    );
