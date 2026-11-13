import 'package:material_ui/material_ui.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';

/// A product photo from the store CDN with a quiet placeholder while it
/// loads and an icon when it cannot be loaded (or there is none).
///
/// Give it a size through its parent (SizedBox, AspectRatio, Expanded).
/// [logicalWidth] is the width it is drawn at, used to ask the CDN for a
/// suitably small file.
///
/// Store photos are shot on white. Pass the colour of the well behind the
/// photo as [wellColor] (usually [AppColors.subtle]) and the photo is
/// multiplied with it, so its white background melts into the well.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.url,
    this.logicalWidth = 160,
    this.fit = BoxFit.contain,
    this.semanticLabel,
    this.wellColor,
  });

  final String? url;
  final double logicalWidth;
  final BoxFit fit;
  final String? semanticLabel;

  /// The colour behind the photo, multiplied into it; null draws the photo
  /// as it is.
  final Color? wellColor;

  /// Requested pixel widths are rounded up to these steps so the same file
  /// is reused between cards, rows and thumbnails.
  static const List<int> _steps = [120, 240, 360, 480, 720, 1080];

  static int _requestWidth(double physical) {
    for (final step in _steps) {
      if (physical <= step) return step;
    }
    return _steps.last;
  }

  @override
  Widget build(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) return const _ImageFallback();
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0);
    final width = _requestWidth(logicalWidth * dpr);
    return Image.network(
      shopifyImageUrl(source, width: width),
      fit: fit,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
      color: wellColor,
      colorBlendMode: wellColor == null ? null : BlendMode.multiply,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) => const _ImageFallback(),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: AppColors.tertiary,
        size: 28,
      ),
    );
  }
}
