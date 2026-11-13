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
/// with the photo in an off-white well, the discount badge, the favourite
/// heart and the add control on the well (top-left, top-right and
/// bottom-right, as on the big grocery apps, so the card has no empty
/// control row), then the name, size line, price and the one-line delivery
/// promise (once a delivery area is set). Tapping it opens product detail.
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

  /// Space under the last line of text.
  static const double bottomPadding = 10;

  /// Inset of the add control's circle (and the "Sold out" tag) from the
  /// well's edges: its 48px touch target sits in the corner.
  static const double wellInset = 6;

  /// Inset of the discount badge and of the heart's circle from the well's
  /// top edge (the heart's 48px touch target sits in the corner).
  static const double topInset =
      (AppDims.controlTarget - FavouriteHeart.circleSize) / 2;

  /// Above this text scale a sale price and its old price may take two
  /// lines on a card (the price keeps the shopper's size), so cards keep
  /// room for both.
  static const double wrapPriceAbove = 1.3;

  /// True when cards at the current text size let the price wrap.
  static bool priceWraps(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) / 10 > wrapPriceAbove;

  /// The fixed height of a card at the current text size. Call it from a
  /// build method: once a delivery area is set the cards grow to make room
  /// for the delivery line, and the caller is rebuilt.
  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style, [int lines = 1]) =>
        scaler.scale(style.fontSize!) * style.height! * lines;
    final hasArea = context.select<DeliveryStore?, bool>(
      (s) => s?.hasArea ?? false,
    );
    final delivery = hasArea
        ? DeliveryPromiseLine.topGap +
              scaler.scale(DeliveryPromiseLine.fontSize) *
                  DeliveryPromiseLine.lineHeight
        : 0.0;
    // The old price's own line when a sale price wraps (large text).
    final secondPriceLine = priceWraps(context)
        ? 2 + line(AppText.oldPrice)
        : 0.0;
    // Border 2, padding 8 + well + gap 8, name, gap 2, size, gap 4,
    // price, delivery, bottom padding, +1 for rounding.
    return 2 +
        padding +
        wellHeight +
        8 +
        line(AppText.productName, 2) +
        2 +
        line(AppText.caption) +
        4 +
        line(AppText.price) +
        secondPriceLine +
        delivery +
        bottomPadding +
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
    final soldOut = variant == null || !variant.available;
    // The heart and the add control are 48px touch targets in the well's
    // corners; their circles sit [topInset] and [wellInset] in.

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
              bottomPadding + 1,
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
                          top: topInset,
                          left: topInset,
                          child: SalePill(percent: percent),
                        ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: FavouriteHeart(product: product),
                      ),
                      Positioned(
                        right: soldOut ? wellInset : 0,
                        bottom: soldOut ? wellInset : 0,
                        child: soldOut
                            ? const _SoldOutTag()
                            : AddControl(product: product, variant: variant),
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
                          wrap: priceWraps(context),
                        ),
                      DeliveryPromiseLine(product: product),
                    ],
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

/// The favourite heart on a product photo: an outline ink heart in a 32px
/// white circle (filled ink heart when saved), in a 48px touch target.
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
    void toggle() => context.read<FavouritesStore>().toggle(product);
    return Semantics(
      button: true,
      toggled: saved,
      label: saved
          ? 'Remove ${product.title} from favourites'
          : 'Add ${product.title} to favourites',
      onTap: toggle,
      excludeSemantics: true,
      child: InkResponse(
        key: ValueKey('favourite-${product.id}'),
        onTap: toggle,
        radius: AppDims.controlTarget / 2,
        child: SizedBox(
          width: AppDims.controlTarget,
          height: AppDims.controlTarget,
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

/// "Sold out" on the image well, in place of the add control: a small
/// white pill with grey text (the photo behind it is dimmed).
class _SoldOutTag extends StatelessWidget {
  const _SoldOutTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const ShapeDecoration(
        color: AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: AppColors.hairline)),
      ),
      child: Text(
        'Sold out',
        style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
