import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../models/money.dart';
import '../services/shopify_api.dart';
import '../state/account_session.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/deliver_to.dart';
import '../widgets/delivery_widgets.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';

/// The Cart tab: where and how the order is delivered, the lines of the
/// cart with steppers and a summary card with the Checkout button resting
/// above the floating bottom bar.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  /// Under the subtotal. The store's own cart says "Duties and taxes
  /// included. Shipping is calculated at checkout."
  static const String vatNote =
      'Prices include VAT. Any delivery fee is shown at checkout.';

  /// Under the subtotal when some lines are sold out.
  static const String soldOutNote = 'Sold-out items are not included.';

  /// Above Checkout when signed in: "Signed in as sara@example.com", or
  /// "Signed in" when the email is not known.
  static String signedInLine(String? email) =>
      email == null ? 'Signed in' : 'Signed in as $email';

  /// Above Checkout when signed out (orders need an account).
  static const String signInNeededLine = 'Sign in needed to order';

  /// The Checkout label with the total: "Checkout · \u20C3 62.50".
  static String checkoutLabel(int cents) => 'Checkout · ${formatMoney(cents)}';

  /// Above the text scale where the summary card stops being pinned and
  /// scrolls with the lines, so it never squeezes them off the screen.
  static const double pinnedSummaryMaxScale = 1.3;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

/// Said when the cart finds lines the store has sold out since.
const String soldOutMessage =
    'Some items are sold out now. They are not included in your order.';

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    _revalidate();
  }

  /// The cart is saved on the device, possibly days ago: bring names and
  /// prices up to date, drop lines the store no longer has and mark the
  /// ones it has sold out since. Each is said once.
  Future<void> _revalidate() async {
    final cart = context.read<CartStore>();
    final soldOutBefore = cart.soldOutLines;
    final removed = await cart.revalidate(context.read<ShopifyApi>());
    if (!mounted) return;
    if (removed > 0) {
      AppNav.showNotice(context, AppNav.removedItemsMessage);
    } else if (cart.soldOutLines > soldOutBefore) {
      AppNav.showNotice(context, soldOutMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final lines = cart.lines;
    final count = cart.itemCount;
    // Pinned above the bar at normal text sizes; at a large font size it
    // scrolls with the lines instead (and its text is never capped).
    final pinned =
        MediaQuery.textScalerOf(context).scale(10) / 10 <=
        CartScreen.pinnedSummaryMaxScale;
    final summary = _SummaryCard(
      subtotalCents: cart.subtotalCents,
      soldOut: cart.soldOutLines > 0,
      canCheckout: cart.hasAvailableLines,
    );

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
                    // A buying CTA: the green button.
                    primary: true,
                  ),
                ),
              )
            else ...[
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    0,
                    AppDims.gutter,
                    pinned ? 16 : AppDims.bottomBarSpace(context),
                  ),
                  // The delivery card, then the lines with hairlines
                  // between them (and, at a large font size, the summary).
                  itemCount: lines.length + (pinned ? 1 : 2),
                  separatorBuilder: (_, index) =>
                      index == 0 || index == lines.length
                      ? const SizedBox(height: 8)
                      : const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Where and how, then to whom (the details checkout
                      // is filled in with).
                      return const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CartDeliveryCard(),
                          SizedBox(height: 8),
                          CartDeliverToCard(),
                        ],
                      );
                    }
                    if (index > lines.length) return summary;
                    final line = lines[index - 1];
                    return _CartRow(
                      key: ValueKey<int>(line.variantId),
                      line: line,
                    );
                  },
                ),
              ),
              if (pinned)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    0,
                    AppDims.gutter,
                    AppDims.bottomBarSpace(context) - 12,
                  ),
                  child: summary,
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

  /// Removes the whole line, with "Undo".
  void _remove(CartStore cart, CartLine line) {
    final index = cart.indexOf(line.variantId);
    cart.remove(line.variantId);
    AppNav.showNotice(
      context,
      'Removed ${line.title} from your cart.',
      actionLabel: 'Undo',
      onAction: () => cart.restoreLine(line, index: index),
    );
  }

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
    final detail = line.detailLine;
    // At a large font size the stepper goes under the price, so the
    // price keeps the shopper's size.
    final stack =
        MediaQuery.textScalerOf(context).scale(10) / 10 >
        CartScreen.pinnedSummaryMaxScale;
    final Widget control = line.available
        ? QuantityStepper(
            quantity: line.quantity,
            style: QuantityStepperStyle.solid,
            onDecrement: () => decrementWithUndo(context, cart, line.variantId),
            onIncrement: line.quantity >= CartStore.maxQuantity
                ? null
                : () => cart.increment(line.variantId),
          )
        : _SoldOutActions(onRemove: () => _remove(cart, line));
    final price = PriceRow(
      priceCents: line.lineTotalCents,
      oldPriceCents: line.available ? line.oldLineTotalCents : null,
    );

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
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      semanticsLabel: line.detailSemantics,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (stack) ...[
                    // A sold-out line's price is struck: it is not counted.
                    Opacity(opacity: line.available ? 1 : 0.6, child: price),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: control,
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: Opacity(
                            opacity: line.available ? 1 : 0.6,
                            child: price,
                          ),
                        ),
                        const SizedBox(width: 8),
                        control,
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

/// In place of the stepper on a line the store has sold out since it was
/// added: "Sold out" and a way to remove it.
class _SoldOutActions extends StatelessWidget {
  const _SoldOutActions({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sold out',
          style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 4),
        TextButton(onPressed: onRemove, child: const Text('Remove')),
      ],
    );
  }
}

class _SummaryCard extends StatefulWidget {
  const _SummaryCard({
    required this.subtotalCents,
    required this.soldOut,
    required this.canCheckout,
  });

  final int subtotalCents;

  /// Some lines are sold out (and not in [subtotalCents]).
  final bool soldOut;

  /// At least one line can be bought.
  final bool canCheckout;

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
    // Never capped: at a large font size the card scrolls with the lines
    // (see CartScreen.pinnedSummaryMaxScale).
    final total = widget.subtotalCents;
    return Container(
      decoration: AppDecor.card.copyWith(boxShadow: AppDecor.floatShadow),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One line when it fits; at a large font size the amount goes
          // under "Subtotal" rather than shrinking.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            children: [
              const Text('Subtotal', style: AppText.cardHeading),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: MoneyText(
                  total,
                  style: AppText.price.copyWith(fontSize: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            widget.soldOut
                ? '${CartScreen.vatNote} ${CartScreen.soldOutNote}'
                : CartScreen.vatNote,
            style: AppText.caption,
          ),
          const _AccountLine(),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: widget.canCheckout ? _checkout : null,
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
                : Text(
                    widget.canCheckout
                        ? CartScreen.checkoutLabel(total)
                        : 'Remove sold-out items to check out',
                    semanticsLabel: widget.canCheckout
                        ? 'Checkout, ${moneySemantics(total)}'
                        : null,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Under the subtotal, above Checkout: who orders. Signed in, a small
/// green check and "Signed in as …"; signed out, a neutral "Sign in
/// needed to order" (no green). Nothing when sign-in is not asked for.
class _AccountLine extends StatelessWidget {
  const _AccountLine();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AccountSession>();
    final signedIn = session.signedIn;
    if (!signedIn && !session.signInNeededToOrder) {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const ValueKey('cart-account-line'),
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              signedIn ? Icons.check_circle_outline : Icons.lock_outline,
              size: 16,
              color: signedIn ? AppColors.green : AppColors.secondary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              signedIn
                  ? CartScreen.signedInLine(session.email)
                  : CartScreen.signInNeededLine,
              style: AppText.caption,
            ),
          ),
        ],
      ),
    );
  }
}
