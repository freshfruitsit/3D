import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../models/money.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/delivery_widgets.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';

/// The Cart tab: where and how the order is delivered, the lines of the
/// cart with steppers and a summary card with the Checkout button resting
/// above the floating bottom bar.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    _revalidate();
  }

  /// The cart is saved on the device, possibly days ago: bring names and
  /// prices up to date and drop lines the store no longer has.
  Future<void> _revalidate() async {
    final removed = await context.read<CartStore>().revalidate(
      context.read<ShopifyApi>(),
    );
    if (removed > 0 && mounted) {
      AppNav.showNotice(context, AppNav.removedItemsMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final lines = cart.lines;
    final count = cart.itemCount;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.gutter,
                16,
                AppDims.gutter,
                12,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text('Cart', style: AppText.title),
                    ),
                  ),
                  if (count > 0)
                    Text(
                      count == 1 ? '1 item' : '$count items',
                      style: AppText.caption,
                    ),
                ],
              ),
            ),
            if (lines.isEmpty)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: AppDims.bottomBarSpace(context),
                  ),
                  child: EmptyView(
                    title: 'Your cart is empty',
                    message:
                        'Add fresh fruit, vegetables and more to get started.',
                    actionLabel: 'Start shopping',
                    onAction: () => AppNav.goToTab(context, AppTab.home),
                  ),
                ),
              )
            else ...[
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    0,
                    AppDims.gutter,
                    16,
                  ),
                  // The delivery card, then the lines with hairlines
                  // between them.
                  itemCount: lines.length + 1,
                  separatorBuilder: (_, index) => index == 0
                      ? const SizedBox(height: 8)
                      : const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) return const CartDeliveryCard();
                    final line = lines[index - 1];
                    return _CartRow(
                      key: ValueKey<int>(line.variantId),
                      line: line,
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppDims.gutter,
                  0,
                  AppDims.gutter,
                  AppDims.bottomBarSpace(context) - 12,
                ),
                child: _SummaryCard(subtotalCents: cart.subtotalCents),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartRow extends StatefulWidget {
  const _CartRow({super.key, required this.line});

  final CartLine line;

  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  bool _opening = false;

  /// Cart lines keep only what the row needs, so the full product is
  /// loaded before product detail opens. A failure leaves the shopper on
  /// the cart.
  Future<void> _openProduct() async {
    final handle = widget.line.handle;
    if (_opening || handle.isEmpty) return;
    setState(() => _opening = true);
    try {
      final product = await context.read<ShopifyApi>().product(handle);
      if (!mounted) return;
      setState(() => _opening = false);
      await AppNav.openProduct(context, product);
    } on ApiException catch (e) {
      if (mounted) AppNav.showNotice(context, e.userMessage);
    } finally {
      if (mounted && _opening) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final cart = context.read<CartStore>();
    final variant = line.variantTitle;

    return InkWell(
      onTap: _openProduct,
      borderRadius: AppDims.wellBorderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(6),
              decoration: AppDecor.well,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: _opening ? 0.4 : 1,
                    child: ProductImage(
                      url: line.imageUrl,
                      logicalWidth: 72,
                      wellColor: AppColors.subtle,
                    ),
                  ),
                  // The product is loading before its page opens.
                  if (_opening)
                    const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.productName,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line.detailLine,
                    semanticsLabel: [
                      ?variant,
                      '${moneySemantics(line.priceCents)} each',
                    ].join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: PriceRow(
                          priceCents: line.lineTotalCents,
                          oldPriceCents: line.oldLineTotalCents,
                        ),
                      ),
                      const SizedBox(width: 8),
                      QuantityStepper(
                        quantity: line.quantity,
                        style: QuantityStepperStyle.solid,
                        onDecrement: () => cart.decrement(line.variantId),
                        onIncrement: line.quantity >= CartStore.maxQuantity
                            ? null
                            : () => cart.increment(line.variantId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({required this.subtotalCents});

  final int subtotalCents;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  /// True while the cart is checked against the store before checkout.
  bool _checking = false;

  Future<void> _checkout() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      await AppNav.openCheckout(context);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capped text scaling keeps the card a bounded height, so the list
    // above always has room.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        decoration: AppDecor.card.copyWith(boxShadow: AppDecor.floatShadow),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('Subtotal', style: AppText.cardHeading),
                const SizedBox(width: 16),
                // Takes the rest of the row so the total sits flush right.
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: MoneyText(
                      widget.subtotalCents,
                      style: AppText.price.copyWith(fontSize: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Delivery and taxes are calculated at checkout.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _checkout,
              child: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        // On the green button.
                        color: AppColors.onDark,
                      ),
                    )
                  : const Text('Checkout'),
            ),
          ],
        ),
      ),
    );
  }
}
