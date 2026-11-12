import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';

/// A "Brands We Love" tile: the category tile look with the brand's square
/// image filling the tile and an uppercase label underneath.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, required this.brand, this.onTap});

  final BrandEntry brand;

  /// Defaults to opening Search pre-filled with the brand's search term.
  final VoidCallback? onTap;

  /// Space around the image.
  static const double imagePadding = 6;

  /// Between the image and the label.
  static const double labelGap = 6;

  /// Below the label.
  static const double bottomPadding = 8;

  /// Height of a tile that is [width] wide.
  static double heightFor(BuildContext context, double width) {
    final label = MediaQuery.textScalerOf(context).scale(11) * 1.2;
    // +1 keeps the rounded-up text line from overflowing.
    return width + labelGap + label + bottomPadding + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: brand.name,
      excludeSemantics: true,
      child: Material(
        color: AppColors.tile,
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.cardBorderRadius,
          // Subtle inner edge, as on the category tiles.
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ??
              () => AppNav.openSearch(context, initialQuery: brand.searchTerm),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                imagePadding, imagePadding, imagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      brand.asset,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(height: labelGap),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    brand.name.toUpperCase(),
                    maxLines: 1,
                    style: AppText.tileLabel,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 4-column grid of the brand tiles. Not scrollable: put it in the
/// page's scroll view and add the page gutter around it.
class BrandGrid extends StatelessWidget {
  const BrandGrid({super.key, this.onSelected});

  /// Defaults to opening Search pre-filled with the brand's search term.
  final ValueChanged<BrandEntry>? onSelected;

  static const int _columns = 4;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (constraints.maxWidth - (_columns - 1) * _gap) / _columns;
        return GridView.builder(
          shrinkWrap: true,
          primary: false,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns,
            crossAxisSpacing: _gap,
            mainAxisSpacing: _gap,
            mainAxisExtent: BrandTile.heightFor(context, width),
          ),
          itemCount: Catalog.brands.length,
          itemBuilder: (context, index) {
            final brand = Catalog.brands[index];
            return BrandTile(
              key: ValueKey('brand-$index'),
              brand: brand,
              onTap: onSelected == null ? null : () => onSelected!(brand),
            );
          },
        );
      },
    );
  }
}
