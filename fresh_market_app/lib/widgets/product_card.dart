import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import 'add_control.dart';
import 'delivery_widgets.dart';
import 'price_widgets.dart';
import 'product_image.dart';

/// The product card of rails and grids: photo, sale pill, name, size line,
/// price, the delivery line (once a delivery area is set) and the add
/// control. Tapping it opens product detail.
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
  static const double railWidth = 156;

  /// Gap between cards in rails and grids.
  static const double gap = 12;

  static const double _photoHeight = 132;

  /// The fixed height of a card at the current text size.
  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final name = scaler.scale(AppText.productName.fontSize!) *
        AppText.productName.height! *
        2;
    final size =
        scaler.scale(AppText.caption.fontSize!) * AppText.caption.height!;
    final price =
        scaler.scale(AppText.price.fontSize!) * AppText.price.height!;
    // Room for the delivery line; without an area the name gets it.
    final delivery = scaler.scale(DeliveryPromiseLine.fontSize) *
        DeliveryPromiseLine.lineHeight *
        DeliveryPromiseLine.maxLines;
    // border 2 + photo + top pad 8 + gaps 2 + 4 + 3 + control 44 + bottom 6.
    return (2 + _photoHeight + 8 + 2 + 4 + 3 + AppDims.touch + 6) +
        name +
        size +
        price +
        delivery +
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

    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDims.cardBorderRadius,
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => AppNav.openProduct(context, product),
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _photoHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Opacity(
                        opacity: product.available ? 1 : 0.5,
                        child: ProductImage(
                          url: product.imageUrl,
                          logicalWidth: 170,
                        ),
                      ),
                    ),
                    if (percent != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: SalePill(percent: percent),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
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
                      const SizedBox(height: 3),
                      DeliveryPromiseLine(product: product),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AddControl(product: product, variant: variant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
