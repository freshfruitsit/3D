import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

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

  /// The most lines a label may take.
  static const int labelLines = 2;

  /// Extra height under the label, so rounded-up text lines never
  /// overflow.
  static const double slack = 2;

  /// Height of [lines] label lines at the current text size.
  static double labelHeight(BuildContext context, [int lines = labelLines]) =>
      MediaQuery.textScalerOf(context).scale(AppText.tileLabel.fontSize!) *
      AppText.tileLabel.height! *
      lines;

  /// Height of a tile that is [width] wide, keeping [lines] label lines.
  static double heightFor(
    BuildContext context,
    double width, [
    int lines = labelLines,
  ]) => width + labelGap + labelHeight(context, lines) + slack;

  /// The style [label] is drawn in on a tile [width] wide: the tile label,
  /// as the Text really draws it (inherited style, bold text), at a
  /// smaller size when one of its words would not fit the width on its
  /// own, so no word is broken in two ("Vegetabl|es") at a large font size.
  static TextStyle labelStyle(
    BuildContext context,
    double width,
    String label,
  ) {
    final style = effectiveTextStyle(context, AppText.tileLabel);
    final size = fittingFontSize(
      label,
      style,
      MediaQuery.textScalerOf(context),
      width,
    );
    return size == style.fontSize ? style : style.copyWith(fontSize: size);
  }

  /// How many label lines (1 or 2) the longest of [labels] takes on a tile
  /// [width] wide at the current text size. A grid keeps that many under
  /// every tile, so its rows line up without an empty line when every
  /// name fits on one. Measured with the style the label is drawn in.
  static int linesNeeded(
    BuildContext context,
    double width,
    Iterable<String> labels,
  ) {
    var lines = 1;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle(context, width, label)),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: labelLines,
      )..layout(maxWidth: width);
      final used = painter.computeLineMetrics().length;
      painter.dispose();
      if (used > lines) lines = used.clamp(1, labelLines);
      if (lines == labelLines) break;
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
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
              LayoutBuilder(
                builder: (context, constraints) => Text(
                  label,
                  maxLines: labelLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: labelStyle(context, constraints.maxWidth, label),
                ),
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
      onTap:
          onTap ??
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

  /// Between a row's labels and the next row's squares (plus the tile's
  /// [SquareTile.slack]).
  static const double rowGap = 16;

  /// Width of one tile in a grid [maxWidth] wide.
  static double tileWidth(double maxWidth) =>
      (maxWidth - (columns - 1) * columnGap) / columns;

  /// Free space under the names of the last row of a grid of [labels],
  /// [maxWidth] wide: the [SquareTile.slack], plus a line when the grid
  /// keeps two label lines but no name in the last row needs the second.
  /// A section after the grid takes it off its gap above, so the gap the
  /// eye sees is the same as everywhere else.
  static double trailingSpace(
    BuildContext context,
    double maxWidth,
    List<String> labels,
  ) {
    if (labels.isEmpty) return 0;
    final width = tileWidth(maxWidth);
    final kept = SquareTile.linesNeeded(context, width, labels);
    final lastRowStart = (labels.length - 1) ~/ columns * columns;
    final used = SquareTile.linesNeeded(
      context,
      width,
      labels.sublist(lastRowStart),
    );
    return SquareTile.slack +
        SquareTile.labelHeight(context, kept) -
        SquareTile.labelHeight(context, used);
  }

  /// The grid delegate for a grid of [labels], [maxWidth] wide. Rows keep
  /// two label lines only when a label needs them.
  static SliverGridDelegate delegate(
    BuildContext context,
    double maxWidth, {
    Iterable<String> labels = const [],
  }) {
    final width = tileWidth(maxWidth);
    final lines = labels.isEmpty
        ? SquareTile.labelLines
        : SquareTile.linesNeeded(context, width, labels);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: columnGap,
      mainAxisSpacing: rowGap,
      mainAxisExtent: SquareTile.heightFor(context, width, lines),
    );
  }
}

/// The 4-column grid of the category tiles (all 12, or the first [limit]).
/// Not scrollable: put it in the page's scroll view and add the page
/// gutter around it.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, this.onSelected, this.limit});

  /// Defaults to opening the category's product list.
  final ValueChanged<CategoryEntry>? onSelected;

  /// Shows only the first [limit] categories (Home: two rows, with "See
  /// all" opening the Categories tab).
  final int? limit;

  /// The categories shown with [limit].
  static List<CategoryEntry> shown([int? limit]) =>
      limit == null || limit >= Catalog.categories.length
      ? Catalog.categories
      : Catalog.categories.sublist(0, limit);

  @override
  Widget build(BuildContext context) {
    final categories = shown(limit);
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        shrinkWrap: true,
        primary: false,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: TileGrid.delegate(
          context,
          constraints.maxWidth,
          labels: [for (final c in categories) c.label],
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
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
