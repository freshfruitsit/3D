import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../models/product.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';
import 'a11y.dart';

enum QuantityStepperStyle {
  /// Green fill, white icons and count: the in-cart state of the add
  /// control and the cart lines.
  solid,

  /// Off-white (subtle) fill, ink icons and count: product detail's bottom
  /// bar.
  soft,
}

/// Minus, quantity, plus. Each button is a 48px touch target
/// ([AppDims.controlTarget]); the visible pill is 36px high.
///
/// With [binAtOne] the minus shows a bin at quantity 1 (use it where going
/// below 1 removes the item). A null callback disables that button. The
/// quantity is a live region, so screen readers say the new number after
/// each tap.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    this.style = QuantityStepperStyle.soft,
    this.binAtOne = true,
    this.expand = false,
    this.incrementFocusNode,
  });

  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final QuantityStepperStyle style;
  final bool binAtOne;

  /// Fill the available width instead of hugging the content.
  final bool expand;

  /// Focus node of the plus button, so the add control can move keyboard
  /// and screen-reader focus to it after the + turns into this stepper.
  final FocusNode? incrementFocusNode;

  /// Height of the visible pill inside the touch height.
  static const double pillHeight = 36;

  /// Height of the whole stepper (its touch targets).
  static const double height = AppDims.controlTarget;

  @override
  Widget build(BuildContext context) {
    final solid = style == QuantityStepperStyle.solid;
    final foreground = solid ? AppColors.onDark : AppColors.ink;
    final showBin = binAtOne && quantity <= 1;

    Widget button(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      FocusNode? focusNode,
    }) {
      return Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: InkResponse(
          onTap: onTap,
          focusNode: focusNode,
          radius: height / 2,
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: height,
            height: height,
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
      child: Semantics(
        liveRegion: true,
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
      ),
    );

    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The pill's round ends sit around the minus and plus icons, as
          // the add (+) circle does in its own touch target.
          Positioned.fill(
            left: (height - pillHeight) / 2,
            right: (height - pillHeight) / 2,
            top: (height - pillHeight) / 2,
            bottom: (height - pillHeight) / 2,
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
                button(
                  Icons.add,
                  'Increase quantity',
                  onIncrement,
                  focusNode: incrementFocusNode,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Takes one unit of [variantId] off the cart. When that removes the line,
/// says so above the bottom bar with "Undo" (which puts the line back where
/// it was) instead of dropping it silently. See [AppNav.showNotice] for
/// [noticeBottomMargin].
void decrementWithUndo(
  BuildContext context,
  CartStore cart,
  int variantId, {
  double? noticeBottomMargin,
}) {
  final line = cart.lineOf(variantId);
  if (line == null) return;
  final index = cart.indexOf(variantId);
  cart.decrement(variantId);
  if (cart.quantityOf(variantId) > 0) return;
  AppNav.showNotice(
    context,
    'Removed ${line.title} from your cart.',
    bottomMargin: noticeBottomMargin,
    actionLabel: 'Undo',
    onAction: () => cart.restoreLine(line, index: index),
  );
}

/// The add-to-cart control of cards and rows, wired to the [CartStore].
///
/// Not in the cart: a 36px green circle with a white plus in a 48px touch
/// target. In the cart: a green stepper pill (bin at quantity 1; removing
/// offers "Undo"). Sold out: grey "Sold out" text.
///
/// Adding is said to screen readers ("Added Kiwi. 1 in cart") and focus
/// moves to the stepper's plus, so it is not lost when the + is replaced.
///
/// [variant] defaults to the product's first available variant.
class AddControl extends StatefulWidget {
  const AddControl({
    super.key,
    required this.product,
    this.variant,
    this.noticeBottomMargin,
  });

  final Product product;
  final Variant? variant;

  /// Where the "Removed … Undo" notice sits; see [AppNav.showNotice].
  final double? noticeBottomMargin;

  /// Diameter of the visible green circle.
  static const double circleSize = 36;

  @override
  State<AddControl> createState() => _AddControlState();
}

class _AddControlState extends State<AddControl> {
  final FocusNode _plus = FocusNode(debugLabel: 'stepper plus');

  /// Set when the + was used, until the stepper that replaces it has
  /// taken the focus.
  bool _focusStepper = false;

  @override
  void dispose() {
    _plus.dispose();
    super.dispose();
  }

  void _add(CartStore cart, Variant v) {
    cart.add(widget.product, v);
    final inCart = cart.quantityOf(v.id);
    if (inCart == 0) return;
    announce(context, 'Added ${widget.product.title}. $inCart in cart');
    _focusStepper = true;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final v = widget.variant ?? product.defaultVariant;
    if (v == null || !v.available) return const SoldOutLabel();

    final quantity =
        context.select<CartStore, int>((cart) => cart.quantityOf(v.id));
    final cart = context.read<CartStore>();

    if (quantity > 0) {
      if (_focusStepper) {
        _focusStepper = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _plus.canRequestFocus) _plus.requestFocus();
        });
      }
      return QuantityStepper(
        quantity: quantity,
        style: QuantityStepperStyle.solid,
        incrementFocusNode: _plus,
        onDecrement: () => decrementWithUndo(
          context,
          cart,
          v.id,
          noticeBottomMargin: widget.noticeBottomMargin,
        ),
        onIncrement: quantity >= CartStore.maxQuantity
            ? null
            : () => cart.increment(v.id),
      );
    }

    void add() => _add(cart, v);
    return Semantics(
      button: true,
      label: 'Add ${product.title} to cart',
      onTap: add,
      excludeSemantics: true,
      child: InkResponse(
        onTap: add,
        radius: AppDims.controlTarget / 2,
        child: const SizedBox(
          width: AppDims.controlTarget,
          height: AppDims.controlTarget,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: AddControl.circleSize,
                height: AddControl.circleSize,
                child: Icon(Icons.add, size: 22, color: AppColors.onDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grey "Sold out" text shown in place of the add control (48px high, so
/// rows keep their height).
class SoldOutLabel extends StatelessWidget {
  const SoldOutLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDims.controlTarget,
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
