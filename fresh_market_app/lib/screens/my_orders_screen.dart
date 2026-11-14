import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../delivery/delivery.dart';
import '../models/money.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/customer_account_api.dart';
import '../services/customer_auth.dart';
import '../services/shopify_api.dart';
import '../state/account_session.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/product_image.dart';
import '../widgets/state_views.dart';

/// "My orders" (Account, signed in): the customer's latest orders from
/// Shopify's Customer Account API, newest first. Each card has the order
/// number and its status, the date, item count, total and payment, the
/// first photos and "Buy again". Loading, empty and error states.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  static const String title = 'My orders';
  static const String emptyTitle = 'No orders yet';
  static const String emptyMessage =
      'Orders you place in the app show here, with where they are.';
  static const String signedOutTitle = 'Sign in to see your orders';
  static const String signedOutMessage =
      'Your orders are kept with your Fresh Market account.';
  static const String buyAgain = 'Buy again';

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Today", "Yesterday", "12 Nov", or "12 Nov 2025" in another year
  /// (UAE time).
  static String dateLabel(DateTime processedAt, DateTime now) {
    DateTime uae(DateTime t) =>
        t.toUtc().add(const Duration(minutes: DeliveryConfig.uaeOffsetMinutes));
    final day = uae(processedAt);
    final today = uae(now);
    final d = DateTime.utc(day.year, day.month, day.day);
    final t = DateTime.utc(today.year, today.month, today.day);
    final diff = t.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final text = '${day.day} ${_months[day.month - 1]}';
    return day.year == today.year ? text : '$text ${day.year}';
  }

  /// "Today · 2 items · ⃃ 147.50 · Cash on Delivery".
  static String summaryLine(CustomerOrder order, DateTime now) => [
    dateLabel(order.processedAt, now),
    _items(order),
    formatMoney(order.totalFils),
    ?order.paymentLabel,
  ].join(' · ');

  static String _items(CustomerOrder order) {
    final n = order.itemCount;
    final more = order.moreLines ? '+' : '';
    return n == 1 && !order.moreLines ? '1 item' : '$n$more items';
  }

  /// What "Buy again" says: how many were added, and what could not be.
  static String buyAgainMessage({required int added, required int missing}) {
    if (added == 0) return "These items aren't available right now.";
    final first = added == 1
        ? 'Added 1 item to your cart.'
        : 'Added $added items to your cart.';
    if (missing == 0) return first;
    return missing == 1
        ? "$first 1 item isn't available right now."
        : "$first $missing items aren't available right now.";
  }

  /// The product and variant of a past order's line in the store now, or
  /// null when the store no longer has it. Found through the store's
  /// search by the line's title (Shopify's order lines carry no product
  /// handle).
  static Future<(Product, Variant)?> findVariant(
    ShopifyApi api,
    OrderLine line,
  ) async {
    final id = line.variantId;
    if (id == null || line.title.trim().isEmpty) return null;
    try {
      for (final product in await api.search(line.title, limit: 6)) {
        final variant = product.variantById(id);
        if (variant != null) return (product, variant);
      }
    } on ApiException {
      // Not found right now.
    }
    return null;
  }

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

enum _Load { loading, loaded, failed, signedOut }

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  _Load _state = _Load.loading;
  List<CustomerOrder> _orders = const [];
  String _error = '';
  String? _buying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<AccountSession>();
    final api = context.read<CustomerAccountApi>();
    if (_state != _Load.loading) setState(() => _state = _Load.loading);
    try {
      var token = await session.accessToken();
      if (token == null) {
        if (mounted) setState(() => _state = _Load.signedOut);
        return;
      }
      List<CustomerOrder> orders;
      try {
        orders = await api.orders(token);
      } on CustomerApiUnauthorized {
        token = await session.accessToken(forceRefresh: true);
        if (token == null) {
          if (mounted) setState(() => _state = _Load.signedOut);
          return;
        }
        orders = await api.orders(token);
      }
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _state = _Load.loaded;
      });
    } on CustomerApiUnauthorized {
      if (mounted) setState(() => _state = _Load.signedOut);
    } on CustomerApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _state = _Load.failed;
      });
    } on AuthNetworkError {
      if (!mounted) return;
      setState(() {
        _error = const CustomerApiNetworkError().userMessage;
        _state = _Load.failed;
      });
    }
  }

  Future<void> _signIn() async {
    if (await AppNav.signIn(context, noticeBottomMargin: AppDims.gutter) &&
        mounted) {
      await _load();
    }
  }

  /// Puts what can still be bought from [order] in the cart, as many as
  /// were ordered, and says what happened (with "View cart").
  Future<void> _buyAgain(CustomerOrder order) async {
    if (_buying != null) return;
    final api = context.read<ShopifyApi>();
    final cart = context.read<CartStore>();
    setState(() => _buying = order.id);
    try {
      final lines = order.lines.where((l) => l.variantId != null).toList();
      final found = await Future.wait(
        lines.map((line) => MyOrdersScreen.findVariant(api, line)),
      );
      var added = 0;
      var missing = order.lines.length - lines.length;
      for (final (i, hit) in found.indexed) {
        if (hit == null || !hit.$2.available) {
          missing++;
          continue;
        }
        cart.add(hit.$1, hit.$2, quantity: lines[i].quantity);
        added += lines[i].quantity;
      }
      if (!mounted) return;
      AppNav.showNotice(
        context,
        MyOrdersScreen.buyAgainMessage(added: added, missing: missing),
        bottomMargin: AppDims.gutter,
        actionLabel: added > 0 ? 'View cart' : null,
        onAction: added > 0 ? () => AppNav.goToTab(context, AppTab.cart) : null,
      );
    } finally {
      if (mounted) setState(() => _buying = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = context.read<DeliveryStore>().now();
    final Widget body = switch (_state) {
      _Load.loading => ListView(
        key: const ValueKey('orders-loading'),
        padding: const EdgeInsets.fromLTRB(
          AppDims.gutter,
          8,
          AppDims.gutter,
          24,
        ),
        children: [
          Semantics(
            label: 'Loading your orders',
            child: const Column(
              children: [
                _CardSkeleton(),
                SizedBox(height: 12),
                _CardSkeleton(),
                SizedBox(height: 12),
                _CardSkeleton(),
              ],
            ),
          ),
        ],
      ),
      _Load.failed => ErrorView(
        key: const ValueKey('orders-error'),
        message: _error,
        onRetry: _load,
      ),
      _Load.signedOut => _SignedOut(onSignIn: _signIn),
      _Load.loaded when _orders.isEmpty => EmptyView(
        key: const ValueKey('orders-empty'),
        icon: Icons.shopping_bag_outlined,
        title: MyOrdersScreen.emptyTitle,
        message: MyOrdersScreen.emptyMessage,
        actionLabel: 'Start shopping',
        onAction: () => AppNav.goToTab(context, AppTab.home),
      ),
      _Load.loaded => RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          key: const ValueKey('orders-list'),
          padding: const EdgeInsets.fromLTRB(
            AppDims.gutter,
            8,
            AppDims.gutter,
            24,
          ),
          itemCount: _orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _OrderCard(
            order: _orders[i],
            now: now,
            buying: _buying == _orders[i].id,
            onBuyAgain: _buying == null ? () => _buyAgain(_orders[i]) : null,
          ),
        ),
      ),
    };
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.gutter,
                8,
                AppDims.gutter,
                8,
              ),
              child: Row(
                children: [
                  CircleIconButton.back(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: const Text(
                        MyOrdersScreen.title,
                        style: AppText.title,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// One order: number, status pill, the summary line, photos, Buy again.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.now,
    required this.buying,
    required this.onBuyAgain,
  });

  final CustomerOrder order;
  final DateTime now;
  final bool buying;
  final VoidCallback? onBuyAgain;

  @override
  Widget build(BuildContext context) {
    final photos = order.lines.where((l) => l.imageUrl != null).toList();
    final shown = photos.take(4).toList();
    final more = order.lines.length - shown.length;
    final summary = MyOrdersScreen.summaryLine(order, now);
    final canBuyAgain = order.lines.any((l) => l.variantId != null);
    return Container(
      key: ValueKey('order-${order.name}'),
      decoration: AppDecor.card,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label:
                'Order ${order.name}, ${order.status.label}. '
                '${summary.replaceAll(formatMoney(order.totalFils), moneySemantics(order.totalFils))}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(order.name, style: AppText.cardHeading),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(status: order.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  summary,
                  style: AppText.bodySmall.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
          ),
          if (shown.isNotEmpty || canBuyAgain) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final line in shown)
                          Container(
                            width: 44,
                            height: 44,
                            padding: const EdgeInsets.all(4),
                            decoration: AppDecor.well,
                            child: ProductImage(
                              url: line.imageUrl,
                              logicalWidth: 44,
                              wellColor: AppColors.subtle,
                            ),
                          ),
                        if (more > 0 && shown.isNotEmpty)
                          Text('+$more', style: AppText.label),
                      ],
                    ),
                  ),
                ),
                if (canBuyAgain) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    key: ValueKey('buy-again-${order.name}'),
                    style: AppButtons.outline.copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                        Size(64, AppDims.touch),
                      ),
                    ),
                    onPressed: onBuyAgain,
                    child: buying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            MyOrdersScreen.buyAgain,
                            semanticsLabel: 'Buy again, order ${order.name}',
                          ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Placed", "On the way" (green, as a delivery highlight), "Delivered".
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      OrderStatus.onTheWay => (AppColors.greenSoft, AppColors.green),
      OrderStatus.placed => (AppColors.subtle, AppColors.ink),
      _ => (AppColors.subtle, AppColors.secondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppDims.pillBorderRadius,
      ),
      child: Text(
        status.label,
        style: AppText.tag.copyWith(color: foreground, fontSize: 12),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.card,
      padding: const EdgeInsets.all(16),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 64, height: 14),
          SizedBox(height: 10),
          SkeletonBox(width: 220, height: 10),
          SizedBox(height: 14),
          Row(
            children: [
              SkeletonBox(width: 44, height: 44, radius: 12),
              SizedBox(width: 8),
              SkeletonBox(width: 44, height: 44, radius: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// The session ended (Shopify refused the refresh): sign in again.
class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          key: const ValueKey('orders-signed-out'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.subtle,
                child: Icon(Icons.lock_outline, size: 32, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: const Text(
                MyOrdersScreen.signedOutTitle,
                textAlign: TextAlign.center,
                style: AppText.heading,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              MyOrdersScreen.signedOutMessage,
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: AppButtons.dark,
              onPressed: onSignIn,
              child: const Text('Sign in with email'),
            ),
          ],
        ),
      ),
    );
  }
}
