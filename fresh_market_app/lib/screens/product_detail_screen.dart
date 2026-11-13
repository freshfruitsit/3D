import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../state/cart_store.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/delivery_widgets.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';

/// One product, full screen (no bottom bar): photo panel with back,
/// favourite and cart buttons, variant choice, when it can be delivered,
/// facts, description and a sticky bar with the quantity and "Add to
/// cart".
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  /// Always a full product (with variants).
  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Variant? _variant = widget.product.defaultVariant;
  int _quantity = 1;

  /// What the last "Add to cart" put in the cart; null until then, and
  /// again once another weight is chosen.
  String? _addedMessage;

  final ScrollController _scroll = ScrollController();

  Product get _product => widget.product;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _selectVariant(Variant variant) {
    if (variant.id == _variant?.id) return;
    setState(() {
      _variant = variant;
      _quantity = 1;
      _addedMessage = null;
    });
  }

  /// "Added to cart · 3 in your cart": says what this tap added and what
  /// the cart now holds, so it changes (and is read out) on every add.
  static String addedMessage(int added, int inCart) =>
      '${added == 1 ? 'Added to cart' : '$added added to cart'} · '
      '${inCartMessage(inCart)}';

  /// "3 in your cart".
  static String inCartMessage(int inCart) => '$inCart in your cart';

  void _addToCart(CartStore cart, Variant variant, int quantity) {
    cart.add(_product, variant, quantity: quantity);
    setState(() {
      _addedMessage = addedMessage(quantity, cart.quantityOf(variant.id));
      _quantity = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final variant = _variant;
    final cart = context.watch<CartStore>();

    final canBuy = variant != null && variant.available;
    final inCart = variant == null ? 0 : cart.quantityOf(variant.id);
    // How many more of this variant the cart can still take.
    final room = variant == null ? 0 : CartStore.maxQuantity - inCart;
    final quantity = room < 1 ? 1 : _quantity.clamp(1, room);

    final sizeLine = product.sizeLine(variant);
    final facts = product.facts;
    final description = product.description;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            // No top SafeArea: the photo area runs behind the status bar.
            // The round buttons float above the page, so back, favourite
            // and cart stay in reach however far it is scrolled.
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PhotoPanel(product: product),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppDims.gutter,
                            20,
                            AppDims.gutter,
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (product.vendor.isNotEmpty) ...[
                                Text(product.vendor, style: AppText.caption),
                                const SizedBox(height: 4),
                              ],
                              Semantics(
                                header: true,
                                child: Text(
                                  product.title,
                                  style: AppText.title,
                                ),
                              ),
                              if (sizeLine.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  sizeLine,
                                  style: AppText.body.copyWith(
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                              if (variant != null) ...[
                                const SizedBox(height: 12),
                                PriceRow(
                                  priceCents: variant.priceCents,
                                  oldPriceCents: variant.oldPriceCents,
                                  large: true,
                                  trailing: variant.salePercent == null
                                      ? null
                                      : SalePill(percent: variant.salePercent!),
                                ),
                              ],
                              // The weights sit right under the price they change.
                              if (product.hasVariantChoice) ...[
                                const SizedBox(height: 24),
                                Text(
                                  product.optionName,
                                  style: AppText.cardHeading,
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    for (final v in product.variants)
                                      _VariantButton(
                                        variant: v,
                                        selected: v.id == variant?.id,
                                        onTap: () => _selectVariant(v),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 24),
                              ProductDeliveryInfo(product: product),
                              if (facts.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final fact in facts)
                                      _FactChip(fact: fact),
                                  ],
                                ),
                              ],
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Semantics(
                                  header: true,
                                  child: const Text(
                                    'About this product',
                                    style: AppText.cardHeading,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  description,
                                  style: AppText.body.copyWith(
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // A white bar fades in behind the round buttons once the
                // photo has scrolled away, so the text never runs under
                // them.
                _TopBar(scroll: _scroll),
                _RoundButtons(product: product, cartCount: cart.itemCount),
              ],
            ),
          ),
          _BuyBar(
            addedMessage: _addedMessage,
            inCartMessage: inCart > 0 ? inCartMessage(inCart) : null,
            onViewCart: () => AppNav.goToTab(context, AppTab.cart),
            quantity: quantity,
            onDecrement: canBuy && quantity > 1
                ? () => setState(() => _quantity = quantity - 1)
                : null,
            onIncrement: canBuy && quantity < room
                ? () => setState(() => _quantity = quantity + 1)
                : null,
            buttonLabel: !canBuy
                ? 'Sold out'
                : room < 1
                ? 'Limit reached'
                : 'Add to cart · '
                      '${formatMoney(variant.priceCents * quantity)}',
            buttonSemantics: canBuy && room >= 1
                ? 'Add to cart, '
                      '${moneySemantics(variant.priceCents * quantity)}'
                : null,
            onAdd: canBuy && room >= 1
                ? () => _addToCart(cart, variant, quantity)
                : null,
          ),
        ],
      ),
    );
  }
}

/// The round white back, favourite and cart buttons, floating at the top
/// of the page (over the photo area, and over the text once scrolled).
class _RoundButtons extends StatelessWidget {
  const _RoundButtons({required this.product, required this.cartCount});

  final Product product;
  final int cartCount;

  @override
  Widget build(BuildContext context) {
    final favourites = context.watch<FavouritesStore>();
    final isFavourite = favourites.contains(product.id);
    final top = MediaQuery.paddingOf(context).top + 8;
    return Positioned(
      top: top,
      left: AppDims.gutter,
      right: AppDims.gutter,
      child: Row(
        children: [
          CircleIconButton.back(context),
          const Spacer(),
          CircleIconButton(
            icon: isFavourite ? Icons.favorite : Icons.favorite_border,
            // Ink either way: filled when on, outlined when off.
            iconColor: AppColors.ink,
            tooltip: isFavourite
                ? 'Remove from favourites'
                : 'Add to favourites',
            toggled: isFavourite,
            onPressed: () => favourites.toggle(product),
          ),
          const SizedBox(width: 10),
          CircleIconButton(
            icon: Icons.shopping_bag_outlined,
            tooltip: 'Cart',
            semanticLabel: cartCount > 0
                ? 'Cart, $cartCount ${cartCount == 1 ? 'item' : 'items'}'
                : 'Cart',
            badgeCount: cartCount,
            onPressed: () => AppNav.goToTab(context, AppTab.cart),
          ),
        ],
      ),
    );
  }
}

/// A white bar with a hairline behind the status bar and the round
/// buttons. Invisible over the photo; it fades in over the last
/// [fadeDistance] before the photo has scrolled under the buttons, so the
/// title and text never show between them.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.scroll});

  final ScrollController scroll;

  /// The buttons' row (44) and the space around it.
  static const double height = 60;
  static const double fadeDistance = 40;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final photo = _PhotoPanel.heightIn(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: top + height,
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: scroll,
          builder: (context, _) {
            final offset = scroll.hasClients ? scroll.offset : 0.0;
            // 0 until the photo's bottom reaches the bar, 1 once it has.
            final start = photo - height - fadeDistance;
            final t = ((offset - start) / fadeDistance).clamp(0.0, 1.0);
            if (t == 0) return const SizedBox.shrink();
            return Opacity(
              opacity: t,
              child: const DecoratedBox(
                key: ValueKey('detail-top-bar'),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.hairline)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The photo(s) on a full-width off-white area that runs behind the status
/// bar (the round buttons float above it, see [_RoundButtons]).
class _PhotoPanel extends StatefulWidget {
  const _PhotoPanel({required this.product});

  final Product product;

  /// Height of the photo area below the status bar, as a share of the
  /// screen width (capped on large screens).
  static const double heightFactor = 0.92;
  static const double maxHeight = 440;

  /// The whole panel's height, status bar included.
  static double heightIn(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      (MediaQuery.sizeOf(context).width * heightFactor).clamp(0.0, maxHeight);

  @override
  State<_PhotoPanel> createState() => _PhotoPanelState();
}

class _PhotoPanelState extends State<_PhotoPanel> {
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final images = product.images;
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    final height = (width * _PhotoPanel.heightFactor).clamp(
      0.0,
      _PhotoPanel.maxHeight,
    );

    // Clear of the round buttons above and the page dots below.
    Widget photo(String? url) => Padding(
      padding: const EdgeInsets.fromLTRB(40, 64, 40, 36),
      child: Opacity(
        opacity: product.available ? 1 : 0.5,
        child: ProductImage(
          url: url,
          logicalWidth: width,
          semanticLabel: product.title,
          wellColor: AppColors.subtle,
        ),
      ),
    );

    return ColoredBox(
      color: AppColors.subtle,
      child: Padding(
        padding: EdgeInsets.only(top: top),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: images.length > 1
                    ? PageView.builder(
                        controller: _pages,
                        itemCount: images.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => photo(images[i]),
                      )
                    : photo(product.imageUrl),
              ),
              if (images.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              // Ink when current, grey otherwise, as on the
                              // Home banners.
                              color: i == _page
                                  ? AppColors.ink
                                  : AppColors.tertiary.withValues(alpha: 0.45),
                              borderRadius: const BorderRadius.all(
                                Radius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One weight/size choice: name with its price beneath. White with a
/// hairline; the chosen one has a 2px ink border. Sold out is greyed,
/// disabled and says so.
class _VariantButton extends StatelessWidget {
  const _VariantButton({
    required this.variant,
    required this.selected,
    required this.onTap,
  });

  final Variant variant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final soldOut = !variant.available;
    final BorderSide edge;
    if (selected) {
      edge = BorderSide(
        color: soldOut ? AppColors.disabledText : AppColors.ink,
        width: 2,
      );
    } else {
      edge = const BorderSide(color: AppColors.hairline);
    }
    // "500 g", not the store's "500 GM".
    final name = formatSize(variant.label) ?? 'Standard';

    return Semantics(
      button: true,
      enabled: !soldOut,
      selected: selected,
      label: soldOut
          ? '$name, sold out'
          : '$name, ${moneySemantics(variant.priceCents)}',
      onTap: soldOut ? null : onTap,
      excludeSemantics: true,
      child: Material(
        color: soldOut ? AppColors.subtle : AppColors.surface,
        // The border is painted over the content, so the 2px selected edge
        // does not move the text.
        shape: RoundedRectangleBorder(
          borderRadius: AppDims.controlBorderRadius,
          side: edge,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: soldOut ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 104, minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: soldOut ? AppColors.disabledText : AppColors.ink,
                      decoration: soldOut ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.disabledText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    soldOut ? 'Sold out' : variant.priceText,
                    style: AppText.caption.copyWith(
                      color: soldOut ? AppColors.disabledText : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small off-white pill for a fact read from the product's tags. The
/// Express bolt is green (an Express mark); the other icons are grey.
class _FactChip extends StatelessWidget {
  const _FactChip({required this.fact});

  final ProductFact fact;

  IconData get _icon => switch (fact) {
    ProductFact.express => Icons.bolt,
    ProductFact.local => Icons.eco_outlined,
    ProductFact.byAir => Icons.flight,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const BoxDecoration(
        color: AppColors.subtle,
        borderRadius: AppDims.pillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon,
            size: 16,
            color: fact == ProductFact.express
                ? AppColors.green
                : AppColors.secondary,
          ),
          const SizedBox(width: 6),
          Text(fact.label, style: AppText.label),
        ],
      ),
    );
  }
}

/// Sticky white bar with a hairline: the "Added to cart" confirmation
/// (after adding), the quantity stepper and the green add button.
class _BuyBar extends StatelessWidget {
  const _BuyBar({
    required this.addedMessage,
    required this.inCartMessage,
    required this.onViewCart,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    required this.buttonLabel,
    required this.buttonSemantics,
    required this.onAdd,
  });

  /// The success notice right after adding (green check on green-soft).
  final String? addedMessage;

  /// "3 in your cart" whenever this weight is in the cart (ink, on
  /// off-white), so the page never suggests the cart is empty.
  final String? inCartMessage;
  final VoidCallback onViewCart;
  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final String buttonLabel;

  /// What screen readers hear for the button (the amount as "AED"); null
  /// reads [buttonLabel].
  final String? buttonSemantics;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final message = addedMessage;
    final inCart = inCartMessage;
    return DecoratedBox(
      decoration: AppDecor.stickyBar,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDims.gutter,
            12,
            AppDims.gutter,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: message == null && inCart == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AddedBanner(
                          message: message ?? inCart!,
                          success: message != null,
                          onViewCart: onViewCart,
                        ),
                      ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: 124,
                    child: QuantityStepper(
                      quantity: quantity,
                      onDecrement: onDecrement,
                      onIncrement: onIncrement,
                      binAtOne: false,
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onAdd,
                      // Two lines at a large font size, never shrunk.
                      child: Text(
                        buttonLabel,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        semanticsLabel: buttonSemantics,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The notice above the buy bar's buttons, with an ink "View cart" link:
/// right after adding, the success notice (green check on green-soft);
/// otherwise how many of this weight are in the cart (ink bag on
/// off-white).
class _AddedBanner extends StatelessWidget {
  const _AddedBanner({
    required this.message,
    required this.success,
    required this.onViewCart,
  });

  final String message;
  final bool success;
  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(success ? 'added-banner' : 'in-cart-banner'),
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(
        color: success ? AppColors.greenSoft : AppColors.subtle,
        borderRadius: AppDims.controlBorderRadius,
      ),
      child: Row(
        children: [
          success
              ? const Icon(Icons.check_circle, size: 20, color: AppColors.green)
              : const Icon(
                  Icons.shopping_bag_outlined,
                  size: 20,
                  color: AppColors.ink,
                ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              // Read out after each add (the text changes every time).
              liveRegion: success,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          TextButton(onPressed: onViewCart, child: const Text('View cart')),
        ],
      ),
    );
  }
}
