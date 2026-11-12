/// A store collection as returned by `/collections.json`.
class Collection {
  const Collection({
    required this.id,
    required this.title,
    required this.handle,
    this.imageUrl,
    this.productsCount = 0,
  });

  final int id;
  final String title;
  final String handle;
  final String? imageUrl;
  final int productsCount;

  factory Collection.fromJson(Map<String, dynamic> json) {
    final image = json['image'];
    return Collection(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      handle: (json['handle'] as String?) ?? '',
      imageUrl: image is Map ? image['src'] as String? : null,
      productsCount: (json['products_count'] as num?)?.toInt() ?? 0,
    );
  }
}
