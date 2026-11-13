import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';

/// The square, label-below tile shared by categories and brands: an
/// off-white square (radius 14) holding [image], and the label under it in
/// 12/600 ink, sentence case, two lines at most.
class SquareTile extends StatelessWidget {
  const SquareTile({
    super.key,
    required this.label,
    required this.image,
    required this.onTap,
  });

  final String label;

  /// Fills the square; clip it yourself if it should reach the corners.
  final Widget image;
  final VoidCallback onTap;

  /// Between the square and the label.
  static const double labelGap = 8;

  /// Label lines kept free under every tile, so a grid row lines up.
  static const int labelLines = 2;

  /// Height of the label area at the current text size.
  static double labelHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(AppText.tileLabel.fontSize!) *
      AppText.tileLabel.height! *
      labelLines;

  /// Height of a tile that is [width] wide.
  static double heightFor(BuildContext context, double width) =>
      // +2 keeps rounded-up text lines from overflowing.
      width + labelGap + labelHeight(context) + 2;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppDims.cardBorderRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: AppDims.cardBorderRadius,
                  ),
                  child: image,
                ),
              ),
              const SizedBox(height: labelGap),
              Text(
                label,
                maxLines: labelLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppText.tileLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A "Shop By Category" tile: the cut-out photo on an off-white square,
/// the label below.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.onTap});

  final CategoryEntry category;

  /// Defaults to opening the category's product list.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SquareTile(
      label: category.label,
      onTap: onTap ??
          () => AppNav.openCollection(
                context,
                handle: category.handle,
                title: category.label,
              ),
      image: Padding(
        padding: const EdgeInsets.all(10),
        child: Image.asset(
          category.asset,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

/// Layout of the 4-column tile grids (categories, brands).
abstract final class TileGrid {
  static const int columns = 4;
  static const double columnGap = 12;
  static const double rowGap = 16;

  /// The grid delegate for a grid [maxWidth] wide.
  static SliverGridDelegate delegate(BuildContext context, double maxWidth) {
    final width = (maxWidth - (columns - 1) * columnGap) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: columnGap,
      mainAxisSpacing: rowGap,
      mainAxisExtent: SquareTile.heightFor(context, width),
    );
  }
}

/// The 4-column grid of the 12 category tiles. Not scrollable: put it in
/// the page's scroll view and add the page gutter around it.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, this.onSelected});

  /// Defaults to opening the category's product list.
  final ValueChanged<CategoryEntry>? onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        primary: false,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: TileGrid.delegate(context, constraints.maxWidth),
        itemCount: Catalog.categories.length,
        itemBuilder: (context, index) {
          final category = Catalog.categories[index];
          return CategoryTile(
            key: ValueKey('category-$index'),
            category: category,
            onTap: onSelected == null ? null : () => onSelected!(category),
          );
        },
      ),
    );
  }
}
