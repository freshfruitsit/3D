import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../models/money.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';

/// The Cart tab: the lines of the cart with steppers and a summary card
/// with the Checkout button resting above the floating bottom bar.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

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
                  const Expanded(child: Text('Cart', style: AppText.title)),
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
                  itemCount: lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final line = lines[index];
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
    _opening = true;
    try {
      final product = await context.read<ShopifyApi>().product(handle);
      if (!mounted) return;
      await AppNav.openProduct(context, product);
    } on ApiException {
      // Stay on the cart.
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final cart = context.read<CartStore>();

    return Container(
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _openProduct,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: ProductImage(url: line.imageUrl, logicalWidth: 72),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          line.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.productName,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        line.detailLine,
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
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.subtotalCents});

  final int subtotalCents;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.card.copyWith(boxShadow: AppDecor.floatShadow),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Subtotal', style: AppText.cardHeading),
              ),
              Text(formatMoney(subtotalCents), style: AppText.heading),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Delivery and taxes are calculated at checkout.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => AppNav.openCheckout(context),
            child: const Text('Checkout'),
          ),
        ],
      ),
    );
  }
}
