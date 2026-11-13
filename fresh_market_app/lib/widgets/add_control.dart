import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';

enum QuantityStepperStyle {
  /// Green fill, white icons and count: the in-cart state of the add
  /// control and the cart lines.
  solid,

  /// Off-white (subtle) fill, ink icons and count: product detail's bottom
  /// bar.
  soft,
}

/// Minus, quantity, plus. Each button is a 44px touch target; the visible
/// pill is 36px high.
///
/// With [binAtOne] the minus shows a bin at quantity 1 (use it where going
/// below 1 removes the item). A null callback disables that button.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    this.style = QuantityStepperStyle.soft,
    this.binAtOne = true,
    this.expand = false,
  });

  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final QuantityStepperStyle style;
  final bool binAtOne;

  /// Fill the available width instead of hugging the content.
  final bool expand;

  /// Height of the visible pill inside the 44px touch height.
  static const double pillHeight = 36;

  @override
  Widget build(BuildContext context) {
    final solid = style == QuantityStepperStyle.solid;
    final foreground = solid ? AppColors.onDark : AppColors.ink;
    final showBin = binAtOne && quantity <= 1;

    Widget button(IconData icon, String label, VoidCallback? onTap) {
      return Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: AppDims.touch,
            height: AppDims.touch,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null
                  ? foreground.withValues(alpha: 0.4)
                  : foreground,
            ),
          ),
        ),
      );
    }

    final count = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 22),
      child: Text(
        '$quantity',
        textAlign: TextAlign.center,
        semanticsLabel: 'Quantity $quantity',
        style: AppText.price.copyWith(
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );

    return SizedBox(
      height: AppDims.touch,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            top: (AppDims.touch - pillHeight) / 2,
            bottom: (AppDims.touch - pillHeight) / 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: solid ? AppColors.green : AppColors.subtle,
                borderRadius: AppDims.pillBorderRadius,
              ),
            ),
          ),
          Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                button(
                  showBin ? Icons.delete_outline : Icons.remove,
                  showBin ? 'Remove from cart' : 'Decrease quantity',
                  onDecrement,
                ),
                // Shrinks when a large system font would not fit.
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: count),
                ),
                button(Icons.add, 'Increase quantity', onIncrement),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The add-to-cart control of cards and rows, wired to the [CartStore].
///
/// Not in the cart: a 36px green circle with a white plus in a 44px touch
/// target. In the cart: a green stepper pill (bin at quantity 1).
/// Sold out: grey "Sold out" text.
///
/// [variant] defaults to the product's first available variant.
class AddControl extends StatelessWidget {
  const AddControl({super.key, required this.product, this.variant});

  final Product product;
  final Variant? variant;

  /// Diameter of the visible green circle.
  static const double circleSize = 36;

  @override
  Widget build(BuildContext context) {
    final v = variant ?? product.defaultVariant;
    if (v == null || !v.available) return const SoldOutLabel();

    final quantity =
        context.select<CartStore, int>((cart) => cart.quantityOf(v.id));
    final cart = context.read<CartStore>();

    if (quantity > 0) {
      return QuantityStepper(
        quantity: quantity,
        style: QuantityStepperStyle.solid,
        onDecrement: () => cart.decrement(v.id),
        onIncrement: quantity >= CartStore.maxQuantity
            ? null
            : () => cart.increment(v.id),
      );
    }

    return Semantics(
      button: true,
      label: 'Add ${product.title} to cart',
      excludeSemantics: true,
      child: InkResponse(
        onTap: () => cart.add(product, v),
        radius: 24,
        child: const SizedBox(
          width: AppDims.touch,
          height: AppDims.touch,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: circleSize,
                height: circleSize,
                child: Icon(Icons.add, size: 22, color: AppColors.onDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grey "Sold out" text shown in place of the add control (44px high, so
/// rows keep their height).
class SoldOutLabel extends StatelessWidget {
  const SoldOutLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDims.touch,
      child: Center(
        widthFactor: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Sold out',
            style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
