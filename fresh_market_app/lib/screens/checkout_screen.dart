import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../config/store_config.dart';
import '../delivery/delivery.dart';
import '../models/money.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../profile/customer_details.dart';
import '../services/customer_auth.dart';
import '../services/order_api.dart';
import '../state/account_session.dart';
import '../state/cart_store.dart';
import '../state/profile_store.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/deliver_to.dart';
import '../widgets/details_fields.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';
import 'order_placed_screen.dart';

/// The app's own checkout, pushed from the cart's green Checkout (and the
/// assistant), always through `AppNav.openCheckout`, which signs the
/// shopper in first.
///
/// Sections: DELIVER TO (the saved address and contact, "Change"),
/// DELIVERY (Fresh Market or Express as radio rows), PAYMENT (Cash on
/// Delivery only), ORDER (the order server's quote: lines, subtotal,
/// delivery fee, total) and the driver's instructions. The green "Place
/// order · total" is pinned at the bottom.
///
/// Prices, stock and the delivery fee are the order server's ([Quote]):
/// the quote is asked for again whenever the cart, the area or the mode
/// changes. The cart is emptied only when the order was made (201).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, this.deliveryNote});

  /// Said under DELIVERY when opening checkout changed the delivery
  /// ("Express isn't available in Jumeirah. Switched to Fresh Market.").
  final String? deliveryNote;

  static const String title = 'Checkout';
  static const String deliverToCaption = 'DELIVER TO';
  static const String deliveryCaption = 'DELIVERY';
  static const String paymentCaption = 'PAYMENT';
  static const String instructionsLabel = 'Delivery instructions';

  static const String marketTitle = 'Fresh Market delivery';
  static const String expressTitle = 'Express';
  static const String codTitle = 'Cash on Delivery';
  static const String codSubtitle = 'Pay the driver when your order arrives';
  static const String cashNote = 'You pay in cash when it arrives';
  static const String vatNote = 'Prices include VAT';
  static const String free = 'Free';

  static const String unavailableTitle = "Ordering isn't available yet";
  static const String unavailableMessage =
      "You can't place orders in the app just yet. Your cart is saved.";
  static const String backToCart = 'Back to cart';

  static const String changedTitle = 'Your order changed';
  static const String changedEnd =
      'Check the new total, then place your order.';

  static const String placing = 'Placing your order…';
  static const String needDetailsTitle = 'Add your name and mobile';
  static const String needDetailsLine =
      'The driver uses them to find you and call on arrival.';
  static const String addDetails = 'Add details';
  static const String needAddressTitle = 'Add your delivery address';
  static const String addAddress = 'Add address';
  static const String signInAgain = 'Please sign in again to place your order.';
  static const String signInLabel = 'Sign in';
  static const String tryAgain = 'Try again';

  /// "ORDER · 2 ITEMS".
  static String orderCaption(int items) =>
      'ORDER · ${items == 1 ? '1 ITEM' : '$items ITEMS'}';

  /// The green button's label: "Place order · ⃃ 147.50".
  static String placeLabel(int? totalFils) => totalFils == null
      ? 'Place order'
      : 'Place order · ${formatMoney(totalFils)}';

  /// "Add ⃃ 77.50 more for free delivery".
  static String freeDeliveryHint(int moreFils) =>
      'Add ${formatMoney(moreFils)} more for free delivery';

  /// Under the button when something is missing.
  static String missingLine({required bool details, required bool address}) {
    if (details && address) return 'Add your details and address to order';
    if (address) return 'Add your address to place your order';
    return 'Add your name and mobile to place your order';
  }

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

/// One line of the "Your order changed" notice.
class _Change {
  const _Change(this.text, {this.struck});

  final String text;

  /// A line taken off the order, shown struck through.
  final CartLine? struck;
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late final CartStore _cart;
  late final DeliveryStore _delivery;
  late final ProfileStore _profile;
  late final AccountSession _session;
  late final OrderApi _api;

  Quote? _quote;
  bool _quoting = false;
  OrderApiException? _quoteError;
  int _quoteSeq = 0;
  String? _quoteKey;

  /// "Your order changed": what changed, and the lines taken off.
  List<_Change> _changes = const [];

  bool _placing = false;
  OrderApiException? _placeError;
  bool _signInNeeded = false;

  /// One key per attempt (the same order body); kept for every retry.
  String? _attemptBody;
  String? _idempotencyKey;

  final TextEditingController _instructions = TextEditingController();
  String? _instructionsFor;
  bool _instructionsEdited = false;
  String? _deliveryNote;

  @override
  void initState() {
    super.initState();
    _cart = context.read<CartStore>();
    _delivery = context.read<DeliveryStore>();
    _profile = context.read<ProfileStore>();
    _session = context.read<AccountSession>();
    _api = context.read<OrderApi>();
    _deliveryNote = widget.deliveryNote;
    final address = _profile.addressFor(_delivery.area);
    _instructionsFor = address?.id;
    _instructions.text = address?.instructions ?? '';
    // The first quote shows as loading at once; it is asked for after
    // the first frame (changing a store during build is not allowed).
    _quoting = _api.available;
    _cart.addListener(_inputsChanged);
    _delivery.addListener(_inputsChanged);
    _profile.addListener(_profileChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keepDeliveryAllowed();
      _requote();
    });
  }

  @override
  void dispose() {
    _cart.removeListener(_inputsChanged);
    _delivery.removeListener(_inputsChanged);
    _profile.removeListener(_profileChanged);
    _instructions.dispose();
    super.dispose();
  }

  void _inputsChanged() {
    if (!mounted) return;
    _keepDeliveryAllowed();
    _profileChanged();
    _requote();
  }

  /// The address's delivery instructions fill the field, until the
  /// shopper types in it.
  void _profileChanged() {
    final address = _profile.addressFor(_delivery.area);
    if (address?.id == _instructionsFor) return;
    _instructionsFor = address?.id;
    if (!_instructionsEdited) _instructions.text = address?.instructions ?? '';
    if (mounted) setState(() {});
  }

  /// Every available line comes by Express (each is tagged for it).
  bool get _allExpress {
    final lines = _cart.lines.where((l) => l.available);
    return lines.isNotEmpty && lines.every((l) => l.express == true);
  }

  bool get _expressAllowed => _delivery.expressCovered && _allExpress;

  /// Express chosen for a cart it cannot carry: Fresh Market instead,
  /// and said.
  void _keepDeliveryAllowed() {
    if (!_delivery.isExpress || _expressAllowed) return;
    _delivery.setMode(DeliveryMode.market);
    _deliveryNote =
        'Not every item in your cart comes by Express, so Fresh Market '
        'delivery is selected.';
  }

  List<OrderLineRequest> get _lineRequests => [
    for (final line in _cart.lines)
      if (line.available)
        OrderLineRequest(variantId: line.variantId, quantity: line.quantity),
  ];

  Future<void> _requote({bool force = false}) async {
    final area = _delivery.area;
    final lines = _lineRequests;
    if (!_api.available || area == null || lines.isEmpty) {
      _quoteSeq++;
      if (mounted) setState(() => _quoting = false);
      return;
    }
    final request = DeliveryRequest(mode: _delivery.mode, area: area);
    final key = jsonEncode({
      'lines': [for (final l in lines) l.toJson()],
      'delivery': request.toJson(),
    });
    if (!force && key == _quoteKey) return;
    _quoteKey = key;
    final seq = ++_quoteSeq;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final quote = await _api.quote(lines: lines, delivery: request);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = quote;
        _quoting = false;
      });
      if (quote.problems.isNotEmpty) _applyProblems(quote.problems, quote);
    } on OrderApiException catch (e) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quoting = false;
        _quoteError = e;
        _quoteKey = null;
      });
    }
  }

  /// Takes what the server found into the cart (sold-out lines are marked,
  /// short stock lowers the amount, prices follow the store, Express falls
  /// back to Fresh Market), shows "Your order changed" with a sentence
  /// for each, and says it to screen readers. The cart's change brings a
  /// new quote with the new totals.
  void _applyProblems(List<QuoteProblem> problems, Quote? quote) {
    final changes = <_Change>[];
    for (final problem in problems) {
      final id = problem.variantId;
      final line = id == null ? null : _cart.lineOf(id);
      final name = line?.title ?? quote?.lineOf(id ?? -1)?.title;
      switch (problem.kind) {
        case QuoteProblemKind.soldOut:
          if (id != null) _cart.markSoldOut(id);
          changes.add(
            _Change(
              name == null
                  ? 'Something in your cart just sold out, so we took it off.'
                  : '$name just sold out, so we took it off.',
              struck: line,
            ),
          );
        case QuoteProblemKind.qtyReduced:
          final left = id == null ? null : quote?.lineOf(id)?.quantity;
          if (id != null && left != null) {
            if (left <= 0) {
              _cart.markSoldOut(id);
            } else {
              _cart.setQuantity(id, left);
            }
          }
          changes.add(
            _Change(
              left == null || name == null
                  ? (problem.message.isEmpty
                        ? 'There is less in stock, so we changed the amount.'
                        : problem.message)
                  : 'Only $left of $name left, so we changed the amount.',
            ),
          );
        case QuoteProblemKind.priceChanged:
          final now = id == null ? null : quote?.lineOf(id)?.unitPriceFils;
          if (id != null && now != null) _cart.updatePrice(id, now);
          changes.add(
            _Change(
              name == null || now == null
                  ? 'A price changed since you added it.'
                  : '$name now costs ${formatMoney(now)}.',
            ),
          );
        case QuoteProblemKind.notExpress:
          _delivery.setMode(DeliveryMode.market);
          changes.add(
            _Change(
              name == null
                  ? "Express can't take this order, so it comes with Fresh "
                        'Market delivery.'
                  : "$name isn't on Express, so your order comes with Fresh "
                        'Market delivery.',
            ),
          );
        case QuoteProblemKind.other:
          if (problem.message.isNotEmpty) changes.add(_Change(problem.message));
      }
    }
    if (changes.isEmpty) return;
    setState(() => _changes = changes);
    announce(
      context,
      '${CheckoutScreen.changedTitle}. '
      '${changes.map((c) => c.text).join(' ')} ${CheckoutScreen.changedEnd}',
    );
  }

  // ---- what is missing ---------------------------------------------------

  ContactDetails get _contact => _profile.contact;

  bool get _detailsMissing =>
      _contact.firstName.isEmpty ||
      _contact.lastName.isEmpty ||
      _contact.mobile.isEmpty;

  SavedAddress? get _address => _profile.addressFor(_delivery.area);

  bool get _addressMissing => _address == null;

  bool get _canPlace {
    final quote = _quote;
    return _api.available &&
        !_placing &&
        !_quoting &&
        _quoteError == null &&
        quote != null &&
        quote.itemCount > 0 &&
        !quote.belowMinimum &&
        !_detailsMissing &&
        !_addressMissing;
  }

  OrderRequest? _orderRequest() {
    final area = _delivery.area;
    final address = _address;
    final quote = _quote;
    if (area == null || address == null || quote == null) return null;
    final contact = _contact;
    return OrderRequest(
      lines: _lineRequests,
      delivery: DeliveryRequest(
        mode: _delivery.mode,
        area: area,
        promise: quote.deliveryPromise,
        pin: address.area.pin,
      ),
      address: OrderAddress(
        firstName: contact.firstName,
        lastName: contact.lastName,
        address1: address.address1,
        address2: address.flat,
        city: CustomerInput.cityName(address.area),
        emirate: address.area.emirate,
        phone: contact.mobile,
      ),
      instructions: CustomerInput.cleanNote(_instructions.text),
      expectedTotalFils: quote.totalFils,
    );
  }

  // ---- placing -----------------------------------------------------------

  Future<void> _placeOrder() async {
    if (!_canPlace) return;
    final order = _orderRequest();
    if (order == null) return;
    final body = jsonEncode(order.toJson());
    if (body != _attemptBody || _idempotencyKey == null) {
      _attemptBody = body;
      _idempotencyKey = OrderApi.newIdempotencyKey();
    }
    final key = _idempotencyKey!;
    setState(() {
      _placing = true;
      _placeError = null;
      _signInNeeded = false;
      _changes = const [];
    });
    announce(context, CheckoutScreen.placing);
    final address = _address!;
    final email = _session.email;
    try {
      var token = await _session.accessToken();
      if (token == null) throw const OrderUnauthorized();
      PlacedOrder placed;
      try {
        placed = await _api.placeOrder(
          order,
          accessToken: token,
          idempotencyKey: key,
        );
      } on OrderUnauthorized {
        // Once: a fresh token, then the same order with the same key.
        token = await _session.accessToken(forceRefresh: true);
        if (token == null) rethrow;
        placed = await _api.placeOrder(
          order,
          accessToken: token,
          idempotencyKey: key,
        );
      }
      if (!mounted) return;
      _cart.clear();
      _idempotencyKey = null;
      _attemptBody = null;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderPlacedScreen(
            order: placed,
            deliveryPromise: placed.deliveryPromise.isEmpty
                ? _quote?.deliveryPromise ?? ''
                : placed.deliveryPromise,
            addressLine: '${address.label.label} · ${address.firstLine}',
            email: email,
          ),
        ),
      );
    } on OrderUnauthorized {
      if (!mounted) return;
      setState(() => _signInNeeded = true);
      announce(context, CheckoutScreen.signInAgain);
    } on OrderChanged catch (e) {
      if (!mounted) return;
      _idempotencyKey = null;
      _attemptBody = null;
      _applyProblems(e.problems, e.quote ?? _quote);
      if (_changes.isEmpty) {
        setState(
          () => _changes = const [
            _Change('Something in your order changed since you opened it.'),
          ],
        );
      }
      unawaited(_requote(force: true));
    } on OrderApiException catch (e) {
      if (!mounted) return;
      setState(() => _placeError = e);
      announce(context, e.userMessage);
    } on AuthNetworkError {
      if (!mounted) return;
      const error = OrderNetworkError();
      setState(() => _placeError = error);
      announce(context, error.userMessage);
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  Future<void> _signInAgain() async {
    final signedIn = await AppNav.signIn(context, noticeBottomMargin: 120);
    if (signedIn && mounted) setState(() => _signInNeeded = false);
  }

  Future<void> _chooseMode(DeliveryMode mode) async {
    if (_placing || mode == _delivery.mode) return;
    setState(() => _deliveryNote = null);
    await AppNav.chooseDeliveryMode(context, mode, noticeBottomMargin: 120);
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt with the stores (the promise counts down with the delivery
    // store's ticker).
    context.watch<DeliveryStore>();
    context.watch<CartStore>();
    context.watch<ProfileStore>();
    context.watch<AccountSession>();
    if (!_api.available) return const _Unavailable();

    final quote = _quote;
    final missing = _detailsMissing || _addressMissing;
    return PopScope(
      // Not while the order is on its way to the store.
      canPop: !_placing,
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    4,
                    AppDims.gutter,
                    24,
                  ),
                  children: [
                    if (_changes.isNotEmpty) ...[
                      _ChangedNotice(changes: _changes),
                      const SizedBox(height: 16),
                    ],
                    const _Caption(CheckoutScreen.deliverToCaption),
                    _DeliverToSection(
                      address: _address,
                      contact: _contact,
                      detailsMissing: _detailsMissing,
                      enabled: !_placing,
                    ),
                    const SizedBox(height: 20),
                    const _Caption(CheckoutScreen.deliveryCaption),
                    _DeliverySection(
                      quote: _quoting ? null : quote,
                      expressAllowed: _expressAllowed,
                      allExpress: _allExpress,
                      note: _deliveryNote,
                      onChoose: _chooseMode,
                    ),
                    const SizedBox(height: 20),
                    const _Caption(CheckoutScreen.paymentCaption),
                    const _PaymentSection(),
                    const SizedBox(height: 20),
                    _Caption(
                      CheckoutScreen.orderCaption(
                        quote?.itemCount ??
                            _cart.lines
                                .where((l) => l.available)
                                .fold(0, (n, l) => n + l.quantity),
                      ),
                    ),
                    _OrderSection(
                      quote: quote,
                      loading: _quoting,
                      error: _quoteError,
                      struck: [
                        for (final c in _changes)
                          if (c.struck != null) c.struck!,
                      ],
                      onRetry: () => _requote(force: true),
                    ),
                    const SizedBox(height: 20),
                    DetailsField(
                      key: const ValueKey('checkout-instructions'),
                      controller: _instructions,
                      label: CheckoutScreen.instructionsLabel,
                      optional: true,
                      hint: 'e.g. Call when you arrive',
                      maxLength: CustomerInput.instructionsMax,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => _instructionsEdited = true,
                    ),
                  ],
                ),
              ),
              _BottomBar(
                label: CheckoutScreen.placeLabel(
                  _quoting || quote == null ? null : quote.totalFils,
                ),
                totalFils: _quoting ? null : quote?.totalFils,
                placing: _placing,
                onPressed: _canPlace ? _placeOrder : null,
                missingLine: missing
                    ? CheckoutScreen.missingLine(
                        details: _detailsMissing,
                        address: _addressMissing,
                      )
                    : null,
                problem: _signInNeeded
                    ? _Problem(
                        message: CheckoutScreen.signInAgain,
                        actionLabel: CheckoutScreen.signInLabel,
                        onAction: _signInAgain,
                        ink: true,
                      )
                    : _placeError == null
                    ? null
                    : _problemFor(_placeError!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The calm message over the bar after an order did not go through, and
  /// what fixes it.
  _Problem _problemFor(OrderApiException error) {
    if (error is OrderInvalid) {
      final field = error.field;
      if (field.startsWith('address.phone') ||
          field.startsWith('address.firstName') ||
          field.startsWith('address.lastName')) {
        return _Problem(
          message: error.userMessage,
          actionLabel: 'Edit details',
          onAction: () =>
              AppNav.openMyDetails(context, noticeBottomMargin: 120),
        );
      }
      if (field.startsWith('address') || field.startsWith('delivery')) {
        final address = _address;
        return _Problem(
          message: error.userMessage,
          actionLabel: 'Edit address',
          onAction: () => address == null
              ? addCartAddress(context)
              : AppNav.openAddress(
                  context,
                  address: address,
                  noticeBottomMargin: 120,
                ),
        );
      }
      return _Problem(message: error.userMessage);
    }
    return _Problem(
      message: error.userMessage,
      actionLabel: CheckoutScreen.tryAgain,
      onAction: _placeOrder,
    );
  }
}

/// Back and "Checkout".
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDims.gutter, 8, AppDims.gutter, 8),
      child: Row(
        children: [
          CircleIconButton.back(context),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: const Text(CheckoutScreen.title, style: AppText.title),
            ),
          ),
        ],
      ),
    );
  }
}

/// "DELIVER TO" and the other small caps captions over the sections.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        header: true,
        // Read as words, not spelt out.
        label: text.toLowerCase(),
        excludeSemantics: true,
        child: Text(text, style: AppText.overline),
      ),
    );
  }
}

/// A white card with a hairline (the sections' cards).
class _Card extends StatelessWidget {
  const _Card({super.key, required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// The address card ("Home · Bay Square, Building 5", the flat and area,
/// the name and mobile, "Change"), or what to add first.
class _DeliverToSection extends StatelessWidget {
  const _DeliverToSection({
    required this.address,
    required this.contact,
    required this.detailsMissing,
    required this.enabled,
  });

  final SavedAddress? address;
  final ContactDetails contact;
  final bool detailsMissing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final address = this.address;
    final area = context.select<DeliveryStore, DeliveryArea?>((s) => s.area);
    final children = <Widget>[];
    if (address != null) {
      final flatArea = [
        if (address.flat.isNotEmpty) address.flat,
        address.area.label,
      ].join(' · ');
      final who = CartDeliverToCard.contactLine(contact);
      children.add(
        _Card(
          key: const ValueKey('checkout-address'),
          padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 6, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  addressLabelIcon(address.label),
                  size: 22,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  container: true,
                  label:
                      'Deliver to ${address.semantics}'
                      '${who.isEmpty ? '' : '. $who'}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${address.label.label} · ${address.address1}',
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        flatArea,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                      if (who.isNotEmpty)
                        Text(
                          who,
                          style: AppText.bodySmall.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('checkout-change-address'),
                onPressed: enabled ? () => changeCartAddress(context) : null,
                child: const Text('Change', semanticsLabel: 'Change address'),
              ),
            ],
          ),
        ),
      );
    } else {
      final elsewhere = context.read<ProfileStore>().addressElsewhere(area);
      children.add(
        _Prompt(
          key: const ValueKey('checkout-need-address'),
          icon: Icons.home_outlined,
          title: CheckoutScreen.needAddressTitle,
          line: elsewhere == null
              ? (area == null
                    ? 'The building and flat for the driver.'
                    : 'The building and flat in ${area.name}.')
              : CartDeliverToCard.elsewhereTitle(elsewhere),
          actions: [
            OutlinedButton(
              key: const ValueKey('checkout-add-address'),
              onPressed: enabled ? () => addCartAddress(context) : null,
              child: Text(CartDeliverToCard.addHereLabel(area)),
            ),
            if (elsewhere != null)
              TextButton(
                key: const ValueKey('checkout-choose-address'),
                onPressed: enabled ? () => changeCartAddress(context) : null,
                child: const Text('Choose a saved address'),
              ),
          ],
        ),
      );
    }
    if (detailsMissing) {
      children.add(const SizedBox(height: 8));
      children.add(
        _Prompt(
          key: const ValueKey('checkout-need-details'),
          icon: Icons.person_outline,
          title: CheckoutScreen.needDetailsTitle,
          line: CheckoutScreen.needDetailsLine,
          actions: [
            OutlinedButton(
              key: const ValueKey('checkout-add-details'),
              onPressed: enabled
                  ? () => AppNav.openMyDetails(context, noticeBottomMargin: 120)
                  : null,
              child: const Text(CheckoutScreen.addDetails),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// Something to add before ordering: an icon, a bold title, a line and
/// the way to add it (ink outline, never green).
class _Prompt extends StatelessWidget {
  const _Prompt({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.actions,
  });

  final IconData icon;
  final String title;
  final String line;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.info,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: AppColors.ink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        line,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 34),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fresh Market and Express as radio rows.
class _DeliverySection extends StatelessWidget {
  const _DeliverySection({
    required this.quote,
    required this.expressAllowed,
    required this.allExpress,
    required this.note,
    required this.onChoose,
  });

  /// The quote for the chosen mode; null while it loads.
  final Quote? quote;
  final bool expressAllowed;
  final bool allExpress;
  final String? note;
  final ValueChanged<DeliveryMode> onChoose;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final area = store.area;
    final now = store.now();
    final mode = store.mode;
    final market = area == null ? null : DeliveryRules.market(area, now);
    final express = area == null ? null : DeliveryRules.express(area, now);
    final open = DeliveryRules.formatHour(DeliveryConfig.expressOpen);

    Widget? fee(DeliveryMode rowMode) {
      final q = quote;
      if (rowMode != mode || q == null) return null;
      return q.deliveryFeeFils == 0
          ? Text(
              CheckoutScreen.free,
              style: AppText.price.copyWith(fontSize: 15),
            )
          : MoneyText(q.deliveryFeeFils, style: AppText.price);
    }

    String expressLine;
    String? expressTrailing;
    if (express == null || !express.covered) {
      expressLine = area == null
          ? 'Set your location to check Express'
          : 'Not available in ${area.name} yet';
    } else if (!allExpress) {
      expressLine = 'Selected items only. Not everything in your cart is.';
    } else if (express.open) {
      expressLine = '${express.range} · selected items only';
    } else {
      expressLine = 'Opens $open · selected items only';
      expressTrailing = 'Closed';
    }
    final closedNotice = store.expressClosedNotice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            children: [
              _RadioRow(
                key: const ValueKey('checkout-mode-market'),
                title: CheckoutScreen.marketTitle,
                subtitle: market?.line ?? 'Full range · same day',
                selected: mode == DeliveryMode.market,
                enabled: true,
                trailing: fee(DeliveryMode.market),
                onTap: () => onChoose(DeliveryMode.market),
              ),
              const Divider(height: 1),
              _RadioRow(
                key: const ValueKey('checkout-mode-express'),
                title: CheckoutScreen.expressTitle,
                titleIcon: const Icon(
                  Icons.bolt,
                  size: 18,
                  color: AppColors.green,
                ),
                subtitle: expressLine,
                selected: mode == DeliveryMode.express,
                enabled: expressAllowed,
                // "Closed" says more than the fee (which the total
                // shows anyway).
                trailing: expressTrailing == null
                    ? fee(DeliveryMode.express)
                    : Text(
                        expressTrailing,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                onTap: () => onChoose(DeliveryMode.express),
              ),
            ],
          ),
        ),
        if (note != null || closedNotice != null) ...[
          const SizedBox(height: 8),
          Text(
            note ?? closedNotice!,
            style: AppText.bodySmall.copyWith(color: AppColors.secondary),
          ),
        ],
      ],
    );
  }
}

/// One radio row: an ink radio mark, a bold title (and an icon), a grey
/// line, and something at the end (the fee, "Closed").
class _RadioRow extends StatelessWidget {
  const _RadioRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.titleIcon,
    this.trailing,
  });

  final String title;
  final Widget? titleIcon;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final faded = !enabled && !selected;
    return Semantics(
      container: true,
      button: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 24,
                    color: selected
                        ? AppColors.ink
                        : faded
                        ? AppColors.disabledText
                        : AppColors.tertiary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: faded
                                  ? AppColors.secondary
                                  : AppColors.ink,
                            ),
                          ),
                          if (titleIcon != null)
                            ExcludeSemantics(child: titleIcon!),
                        ],
                      ),
                      Text(
                        subtitle,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cash on Delivery, the one way to pay.
class _PaymentSection extends StatelessWidget {
  const _PaymentSection();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: _RadioRow(
        key: const ValueKey('checkout-cod'),
        title: CheckoutScreen.codTitle,
        subtitle: CheckoutScreen.codSubtitle,
        selected: true,
        enabled: true,
        onTap: () {},
      ),
    );
  }
}

/// The quote: one row per line (photo, title · size, × amount, line
/// total), the sold-out lines struck through, then subtotal, delivery,
/// the free-delivery hint, the total and "Prices include VAT".
class _OrderSection extends StatelessWidget {
  const _OrderSection({
    required this.quote,
    required this.loading,
    required this.error,
    required this.struck,
    required this.onRetry,
  });

  final Quote? quote;
  final bool loading;
  final OrderApiException? error;
  final List<CartLine> struck;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartStore>();
    final quote = this.quote;
    if (error != null && !loading) {
      return _Card(
        key: const ValueKey('checkout-quote-error'),
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 20,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "We couldn't get today's prices. ${error!.userMessage}",
                style: AppText.bodySmall,
              ),
            ),
            TextButton(
              key: const ValueKey('checkout-quote-retry'),
              onPressed: onRetry,
              child: const Text(CheckoutScreen.tryAgain),
            ),
          ],
        ),
      );
    }
    if (quote == null || loading) {
      return Semantics(
        label: "Getting today's prices",
        child: const _Card(
          key: ValueKey('checkout-quote-loading'),
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonLine(width: 220),
              SizedBox(height: 14),
              _SkeletonLine(width: 180),
              SizedBox(height: 22),
              _SkeletonLine(width: 260),
              SizedBox(height: 10),
              _SkeletonLine(width: 120),
            ],
          ),
        ),
      );
    }
    final lines = quote.availableLines;
    final fee = quote.deliveryFeeFils;
    final more = StoreConfig.freeDeliveryFromFils - quote.subtotalFils;
    return _Card(
      key: const ValueKey('checkout-order'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            _LineRow(line: line, cartLine: cart.lineOf(line.variantId)),
          for (final line in struck)
            if (quote.lineOf(line.variantId)?.available != true)
              _StruckRow(line: line),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _SumRow(label: 'Subtotal', fils: quote.subtotalFils),
          const SizedBox(height: 6),
          _SumRow(
            label: 'Delivery',
            fils: fee,
            text: fee == 0 ? CheckoutScreen.free : null,
          ),
          if (fee > 0 && more > 0) ...[
            const SizedBox(height: 2),
            Text(
              CheckoutScreen.freeDeliveryHint(more),
              semanticsLabel:
                  'Add ${moneySemantics(more)} more for free delivery',
              style: AppText.caption,
            ),
          ],
          if (quote.belowMinimum) ...[
            const SizedBox(height: 6),
            Text(
              'The minimum order is ${formatMoney(quote.minOrderFils)}. '
              'Add ${formatMoney(quote.minOrderFils - quote.subtotalFils)} '
              'more to order.',
              style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 10),
          _SumRow(label: 'Total', fils: quote.totalFils, bold: true),
          const SizedBox(height: 2),
          const Text(CheckoutScreen.vatNote, style: AppText.caption),
        ],
      ),
    );
  }
}

/// A grey bar for the loading quote.
class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: (width / 300).clamp(0.2, 1.0),
      child: Container(
        height: 12,
        decoration: const BoxDecoration(
          color: AppColors.skeleton,
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
    );
  }
}

/// "Australian Beef Kofta · 1 kg", the photo and "× 1", the line total.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, this.cartLine});

  final QuoteLine line;
  final CartLine? cartLine;

  @override
  Widget build(BuildContext context) {
    final size = cartLine?.sizeLabel ?? formatSize(line.variantTitle);
    final name = size == null ? line.title : '${line.title} · $size';
    return Semantics(
      container: true,
      label:
          '$name, ${line.quantity} of them, '
          '${moneySemantics(line.lineTotalFils)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(url: cartLine?.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: AppText.productName.copyWith(fontSize: 15)),
                  Text('× ${line.quantity}', style: AppText.caption),
                ],
              ),
            ),
            const SizedBox(width: 8),
            MoneyText(line.lineTotalFils, style: AppText.price),
          ],
        ),
      ),
    );
  }
}

/// A line taken off: struck through and faded, "Sold out" at the end.
class _StruckRow extends StatelessWidget {
  const _StruckRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final size = line.sizeLabel;
    final name = size == null ? line.title : '${line.title} · $size';
    return Semantics(
      container: true,
      label: '$name, sold out, taken off your order',
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('checkout-struck-${line.variantId}'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Opacity(opacity: 0.5, child: _Thumb(url: line.imageUrl)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: AppText.productName.copyWith(
                  fontSize: 15,
                  color: AppColors.secondary,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Sold out',
              style: AppText.bodySmall.copyWith(color: AppColors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: AppDecor.well,
      child: ProductImage(
        url: url,
        logicalWidth: 44,
        wellColor: AppColors.subtle,
      ),
    );
  }
}

/// "Subtotal … ⃃ 122.50"; [bold] for the total.
class _SumRow extends StatelessWidget {
  const _SumRow({
    required this.label,
    required this.fils,
    this.text,
    this.bold = false,
  });

  final String label;
  final int fils;

  /// Shown instead of the amount ("Free").
  final String? text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? AppText.cardHeading.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          )
        : AppText.body;
    final amountStyle = bold
        ? AppText.price.copyWith(fontSize: 20)
        : AppText.body.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          );
    return Semantics(
      container: true,
      label: '$label, ${text ?? moneySemantics(fils)}',
      excludeSemantics: true,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(label, style: style),
          if (text != null)
            Text(text!, style: amountStyle)
          else
            MoneyText(fils, style: amountStyle),
        ],
      ),
    );
  }
}

/// "Your order changed": a saving-orange outline, what changed in plain
/// words, and what to do.
class _ChangedNotice extends StatelessWidget {
  const _ChangedNotice({required this.changes});

  final List<_Change> changes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('checkout-changed'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDims.cardBorderRadius,
        border: Border.all(color: AppColors.saving, width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline,
                size: 22,
                color: AppColors.saving,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CheckoutScreen.changedTitle,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${changes.map((c) => c.text).join(' ')} '
                    '${CheckoutScreen.changedEnd}',
                    style: AppText.bodySmall,
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

/// A calm message over the bar (an order that did not go through) and
/// its action.
class _Problem {
  const _Problem({
    required this.message,
    this.actionLabel,
    this.onAction,
    this.ink = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The action is the ink button ("Sign in"), not a text link.
  final bool ink;
}

/// The white bar pinned at the bottom: a problem (if any), what is
/// missing, the green 52pt "Place order · total" and "You pay in cash
/// when it arrives".
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.label,
    required this.totalFils,
    required this.placing,
    required this.onPressed,
    this.missingLine,
    this.problem,
  });

  final String label;
  final int? totalFils;
  final bool placing;
  final VoidCallback? onPressed;
  final String? missingLine;
  final _Problem? problem;

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
        boxShadow: AppShadows.sticky,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDims.gutter,
            12,
            AppDims.gutter,
            8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (problem != null) ...[
                Container(
                  key: const ValueKey('checkout-problem'),
                  decoration: AppDecor.info,
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 20,
                        color: AppColors.ink,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(problem.message, style: AppText.bodySmall),
                      ),
                      if (problem.actionLabel != null &&
                          problem.onAction != null) ...[
                        const SizedBox(width: 6),
                        if (problem.ink)
                          FilledButton(
                            key: const ValueKey('checkout-problem-action'),
                            style: AppButtons.dark.copyWith(
                              minimumSize: const WidgetStatePropertyAll(
                                Size(64, AppDims.touch),
                              ),
                            ),
                            onPressed: problem.onAction,
                            child: Text(problem.actionLabel!),
                          )
                        else
                          TextButton(
                            key: const ValueKey('checkout-problem-action'),
                            onPressed: problem.onAction,
                            child: Text(problem.actionLabel!),
                          ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (missingLine != null && !placing) ...[
                Text(
                  missingLine!,
                  key: const ValueKey('checkout-missing'),
                  textAlign: TextAlign.center,
                  style: AppText.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const ValueKey('checkout-place-order'),
                onPressed: onPressed,
                child: placing
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.disabledText,
                            ),
                          ),
                          SizedBox(width: 10),
                          Flexible(child: Text(CheckoutScreen.placing)),
                        ],
                      )
                    : Text(
                        label,
                        semanticsLabel: totalFils == null
                            ? 'Place order'
                            : 'Place order, ${moneySemantics(totalFils!)}',
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(height: 6),
              const Text(
                CheckoutScreen.cashNote,
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app was built without an order server: said plainly, with the
/// way back to the cart.
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Header(),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: Column(
                    key: const ValueKey('checkout-unavailable'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          color: AppColors.subtle,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.storefront_outlined,
                          size: 32,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: const Text(
                          CheckoutScreen.unavailableTitle,
                          textAlign: TextAlign.center,
                          style: AppText.heading,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        CheckoutScreen.unavailableMessage,
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () => AppNav.goToTab(context, AppTab.cart),
                        child: const Text(CheckoutScreen.backToCart),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
