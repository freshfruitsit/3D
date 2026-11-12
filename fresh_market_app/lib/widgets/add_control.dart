import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';

enum QuantityStepperStyle {
  /// Green fill, white icons: the in-cart state of the add control.
  solid,

  /// Soft green fill, dark icons: cart rows and product detail.
  soft,
}

/// Minus, quantity, plus. Each button is a 44px touch target.
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

  @override
  Widget build(BuildContext context) {
    final solid = style == QuantityStepperStyle.solid;
    final foreground = solid ? Colors.white : AppColors.ink;
    final showBin = binAtOne && quantity <= 1;

    Widget button(IconData icon, String label, VoidCallback? onTap) {
      return Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: AppDims.touch,
            height: AppDims.touch,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null
                  ? foreground.withValues(alpha: 0.35)
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
        style: TextStyle(
          fontFamily: AppText.family,
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
          // The visible pill is 36px high inside the 44px touch height.
          Positioned.fill(
            top: 4,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: solid ? AppColors.brand : AppColors.tile,
                borderRadius: const BorderRadius.all(Radius.circular(18)),
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
/// target. In the cart: a compact green stepper (bin at quantity 1).
/// Sold out: a grey "Sold out" label.
///
/// [variant] defaults to the product's first available variant.
class AddControl extends StatelessWidget {
  const AddControl({super.key, required this.product, this.variant});

  final Product product;
  final Variant? variant;

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
      child: InkResponse(
        onTap: () => cart.add(product, v),
        radius: 24,
        child: const SizedBox(
          width: AppDims.touch,
          height: AppDims.touch,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(Icons.add, size: 22, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Disabled grey "Sold out" label shown in place of the add control.
class SoldOutLabel extends StatelessWidget {
  const SoldOutLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDims.touch,
      child: Center(
        widthFactor: 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: const BoxDecoration(
            color: AppColors.disabledFill,
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: Text(
            'Sold out',
            style: AppText.caption.copyWith(
              color: AppColors.disabledText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
