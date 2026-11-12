import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';

/// A category tile: deeper green, the cut-out photo straight on the tile,
/// uppercase label.
class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.onTap});

  final CategoryEntry category;

  /// Defaults to opening the category's product list.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.tile,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDims.cardBorderRadius,
        // Subtle inner edge.
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ??
            () => AppNav.openCollection(
                  context,
                  handle: category.handle,
                  title: category.label,
                ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                category.asset,
                width: 60,
                height: 60,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  category.label.toUpperCase(),
                  maxLines: 1,
                  semanticsLabel: category.label,
                  style: AppText.tileLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 4-column grid of the 12 category tiles. Not scrollable: put it in
/// the page's scroll view and add the page gutter around it.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, this.onSelected});

  /// Defaults to opening the category's product list.
  final ValueChanged<CategoryEntry>? onSelected;

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final extent = 10 + 60 + 8 + scaler.scale(11) * 1.2 + 10 + 2 + 2;
    return GridView.builder(
      shrinkWrap: true,
      primary: false,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: _gap,
        mainAxisSpacing: _gap,
        mainAxisExtent: extent,
      ),
      itemCount: Catalog.categories.length,
      itemBuilder: (context, index) {
        final category = Catalog.categories[index];
        return CategoryTile(
          category: category,
          onTap: onSelected == null ? null : () => onSelected!(category),
        );
      },
    );
  }
}
