import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../delivery/delivery_store.dart';
import '../models/product.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';
import 'add_control.dart';
import 'delivery_widgets.dart';
import 'price_widgets.dart';
import 'product_image.dart';

/// The product card of rails and grids: a white card (radius 14, hairline)
/// with the photo in an off-white well, the discount badge and the
/// favourite heart on the well, the name, size line, price, the one-line
/// delivery promise (once a delivery area is set) and the add control at
/// the bottom right. Tapping it opens product detail.
///
/// Rails: wrap in `SizedBox(width: ProductCard.railWidth)` inside a
/// horizontal list of height `ProductCard.heightOf(context)`.
/// Grids: use `ProductCard.gridDelegate(context)`.
class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product, this.onTap});

  final Product product;

  /// Defaults to opening product detail.
  final VoidCallback? onTap;

  /// Card width in horizontal rails: two cards and a peek on a phone.
  static const double railWidth = 152;

  /// Gap between cards in rails and grids.
  static const double gap = 12;

  /// Inner padding of the card around the well and the text.
  static const double padding = 8;

  /// Height of the image well.
  static const double wellHeight = 128;

  /// The fixed height of a card at the current text size. Call it from a
  /// build method: once a delivery area is set the cards grow to make room
  /// for the delivery line, and the caller is rebuilt.
  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style, [int lines = 1]) =>
        scaler.scale(style.fontSize!) * style.height! * lines;
    final hasArea =
        context.select<DeliveryStore?, bool>((s) => s?.hasArea ?? false);
    final delivery = hasArea
        ? DeliveryPromiseLine.topGap +
            scaler.scale(DeliveryPromiseLine.fontSize) *
                DeliveryPromiseLine.lineHeight
        : 0.0;
    // Border 2, padding 8 + well + gap 8, name, gap 2, size, gap 4,
    // price, delivery, control 44, bottom 4, +1 for rounding.
    return 2 +
        padding +
        wellHeight +
        8 +
        line(AppText.productName, 2) +
        2 +
        line(AppText.caption) +
        4 +
        line(AppText.price) +
        delivery +
        AppDims.touch +
        4 +
        1;
  }

  /// Two-column grid of cards with the page gutter left to the caller.
  static SliverGridDelegate gridDelegate(BuildContext context) =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        mainAxisExtent: heightOf(context),
      );

  @override
  Widget build(BuildContext context) {
    final variant = product.defaultVariant;
    final sizeLine = product.sizeLine(variant);
    final percent = variant?.salePercent;

    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: AppDims.cardBorderRadius,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: AppColors.surface,
        shape: AppDecor.cardShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? () => AppNav.openProduct(context, product),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              padding + 1,
              padding + 1,
              padding + 1,
              5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: wellHeight,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: AppDecor.well,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Opacity(
                            opacity: product.available ? 1 : 0.5,
                            child: ProductImage(
                              url: product.imageUrl,
                              logicalWidth: 160,
                              wellColor: AppColors.subtle,
                            ),
                          ),
                        ),
                      ),
                      if (percent != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: SalePill(percent: percent),
                        ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: FavouriteHeart(product: product),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.productName,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sizeLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption,
                      ),
                      const SizedBox(height: 4),
                      if (variant != null)
                        PriceRow(
                          priceCents: variant.priceCents,
                          oldPriceCents: variant.oldPriceCents,
                        ),
                      DeliveryPromiseLine(product: product),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: AddControl(product: product, variant: variant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The favourite heart on a product photo: an outline ink heart in a 32px
/// white circle (filled ink heart when saved), in a 44px touch target.
/// Wired to the [FavouritesStore]; draws nothing when there is none.
class FavouriteHeart extends StatelessWidget {
  const FavouriteHeart({super.key, required this.product});

  final Product product;

  /// Diameter of the white circle.
  static const double circleSize = 32;

  @override
  Widget build(BuildContext context) {
    final saved = context.select<FavouritesStore?, bool?>(
      (s) => s?.contains(product.id),
    );
    if (saved == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      toggled: saved,
      label: saved
          ? 'Remove ${product.title} from favourites'
          : 'Add ${product.title} to favourites',
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey('favourite-${product.id}'),
        onTap: () => context.read<FavouritesStore>().toggle(product),
        radius: 22,
        child: SizedBox(
          width: AppDims.touch,
          height: AppDims.touch,
          child: Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                boxShadow: AppShadows.card,
              ),
              child: SizedBox(
                width: circleSize,
                height: circleSize,
                child: Icon(
                  saved ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
