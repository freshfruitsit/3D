import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';
import 'category_tile.dart';

/// A "Brands We Love" tile: the category tile look, with the brand's photo
/// filling the square (radius 14) and the name below in sentence case.
class BrandTile extends StatelessWidget {
  const BrandTile({super.key, required this.brand, this.onTap});

  final BrandEntry brand;

  /// Defaults to opening Search pre-filled with the brand's search term.
  final VoidCallback? onTap;

  /// Height of a tile that is [width] wide.
  static double heightFor(BuildContext context, double width) =>
      SquareTile.heightFor(context, width);

  @override
  Widget build(BuildContext context) {
    return SquareTile(
      label: brand.name,
      onTap: onTap ??
          () => AppNav.openSearch(context, initialQuery: brand.searchTerm),
      image: ClipRRect(
        borderRadius: AppDims.cardBorderRadius,
        child: Image.asset(
          brand.asset,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        primary: false,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: TileGrid.delegate(context, constraints.maxWidth),
        itemCount: Catalog.brands.length,
        itemBuilder: (context, index) {
          final brand = Catalog.brands[index];
          return BrandTile(
            key: ValueKey('brand-$index'),
            brand: brand,
            onTap: onSelected == null ? null : () => onSelected!(brand),
          );
        },
      ),
    );
  }
}
