import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../app_nav.dart';
import '../models/money.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';

/// After the order server made the order (201): a big soft-green check,
/// "Order placed" and the order number, when it comes and where, what to
/// pay the driver, where the confirmation goes, then the ink "View my
/// orders" and "Continue shopping". Said to screen readers when shown.
class OrderPlacedScreen extends StatefulWidget {
  const OrderPlacedScreen({
    super.key,
    required this.order,
    required this.deliveryPromise,
    required this.addressLine,
    this.email,
  });

  final PlacedOrder order;

  /// "Tomorrow morning before 11 AM".
  final String deliveryPromise;

  /// "Home · Bay Square, Building 5 · Flat 302".
  final String addressLine;

  /// Where Shopify sends the confirmation; null when not known.
  final String? email;

  static const String title = 'Order placed';
  static const String viewOrders = 'View my orders';
  static const String continueShopping = 'Continue shopping';
  static const String cashLine = 'Cash to the driver';

  /// "Order #1001".
  static String orderLine(PlacedOrder order) => 'Order ${order.orderName}';

  /// "Pay ⃃ 147.50 on delivery".
  static String payLine(int fils) => 'Pay ${formatMoney(fils)} on delivery';

  /// "A confirmation is on its way to sara@example.com".
  static String confirmationLine(String? email) => email == null
      ? 'A confirmation is on its way to your email'
      : 'A confirmation is on its way to $email';

  /// What screen readers hear when the screen opens.
  static String announcement(PlacedOrder order) =>
      'Order placed. ${orderLine(order)}. '
      'Pay ${moneySemantics(order.totalFils)} in cash on delivery.';

  @override
  State<OrderPlacedScreen> createState() => _OrderPlacedScreenState();
}

class _OrderPlacedScreenState extends State<OrderPlacedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        announce(context, OrderPlacedScreen.announcement(widget.order));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppDims.gutter,
                  48,
                  AppDims.gutter,
                  24,
                ),
                children: [
                  Center(
                    child: ExcludeSemantics(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: const BoxDecoration(
                          color: AppColors.greenSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Semantics(
                    header: true,
                    child: const Text(
                      OrderPlacedScreen.title,
                      textAlign: TextAlign.center,
                      style: AppText.title,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    OrderPlacedScreen.orderLine(order),
                    key: const ValueKey('order-placed-number'),
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: AppColors.secondary),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: AppDecor.card,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoRow(
                          icon: Icons.local_shipping_outlined,
                          title: widget.deliveryPromise,
                          line: widget.addressLine,
                        ),
                        const SizedBox(height: 14),
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          title: OrderPlacedScreen.payLine(order.totalFils),
                          titleSemantics:
                              'Pay ${moneySemantics(order.totalFils)} on '
                              'delivery',
                          line: OrderPlacedScreen.cashLine,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    OrderPlacedScreen.confirmationLine(widget.email),
                    textAlign: TextAlign.center,
                    style: AppText.bodySmall.copyWith(
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.gutter,
                8,
                AppDims.gutter,
                12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Ink: looking at orders is not buying.
                  FilledButton(
                    key: const ValueKey('order-placed-view-orders'),
                    style: AppButtons.dark,
                    // My orders takes this screen's place (back goes to
                    // the cart, now empty).
                    onPressed: () => AppNav.openOrders(context, replace: true),
                    child: const Text(
                      OrderPlacedScreen.viewOrders,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    key: const ValueKey('order-placed-continue'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(AppDims.controlTarget),
                    ),
                    onPressed: () => AppNav.goToTab(context, AppTab.home),
                    child: const Text(
                      OrderPlacedScreen.continueShopping,
                      textAlign: TextAlign.center,
                    ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.line,
    this.titleSemantics,
  });

  final IconData icon;
  final String title;
  final String? titleSemantics;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${titleSemantics ?? title}. $line',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 22, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  line,
                  style: AppText.bodySmall.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
