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

  /// What the last "Add to cart" put in the cart; null until then.
  String? _addedMessage;

  Product get _product => widget.product;

  void _selectVariant(Variant variant) {
    if (variant.id == _variant?.id) return;
    setState(() {
      _variant = variant;
      _quantity = 1;
    });
  }

  void _addToCart(CartStore cart, Variant variant, int quantity) {
    cart.add(_product, variant, quantity: quantity);
    setState(() {
      _addedMessage = quantity == 1 ? 'Added to cart' : '$quantity added to cart';
      _quantity = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final variant = _variant;
    final cart = context.watch<CartStore>();

    final canBuy = variant != null && variant.available;
    // How many more of this variant the cart can still take.
    final room = variant == null
        ? 0
        : CartStore.maxQuantity - cart.quantityOf(variant.id);
    final quantity = room < 1 ? 1 : _quantity.clamp(1, room);

    final sizeLine = product.sizeLine(variant);
    final facts = product.facts;
    final description = product.description;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            // No top SafeArea: the photo area runs behind the status bar.
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoPanel(product: product, cartCount: cart.itemCount),
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
                          child: Text(product.title, style: AppText.title),
                        ),
                        if (sizeLine.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            sizeLine,
                            style: AppText.body
                                .copyWith(color: AppColors.secondary),
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
                          Text(product.optionName, style: AppText.cardHeading),
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
                              for (final fact in facts) _FactChip(fact: fact),
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
                            style: AppText.body
                                .copyWith(color: AppColors.secondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _BuyBar(
            addedMessage: _addedMessage,
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

/// The photo(s) on a full-width off-white area that runs behind the status
/// bar, with round white back, favourite and cart buttons on top.
class _PhotoPanel extends StatefulWidget {
  const _PhotoPanel({required this.product, required this.cartCount});

  final Product product;
  final int cartCount;

  /// Height of the photo area below the status bar, as a share of the
  /// screen width (capped on large screens).
  static const double heightFactor = 0.92;
  static const double maxHeight = 440;

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
    final favourites = context.watch<FavouritesStore>();
    final isFavourite = favourites.contains(product.id);
    final width = MediaQuery.sizeOf(context).width;
    final top = MediaQuery.paddingOf(context).top;
    final height = (width * _PhotoPanel.heightFactor)
        .clamp(0.0, _PhotoPanel.maxHeight);

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
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(3)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                top: 8,
                left: AppDims.gutter,
                child: CircleIconButton.back(context),
              ),
              Positioned(
                top: 8,
                right: AppDims.gutter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleIconButton(
                      icon:
                          isFavourite ? Icons.favorite : Icons.favorite_border,
                      // Ink either way: filled when on, outlined when off.
                      iconColor: AppColors.ink,
                      tooltip: isFavourite
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                      onPressed: () => favourites.toggle(product),
                    ),
                    const SizedBox(width: 10),
                    CircleIconButton(
                      icon: Icons.shopping_bag_outlined,
                      tooltip: 'Cart',
                      badgeCount: widget.cartCount,
                      onPressed: () => AppNav.goToTab(context, AppTab.cart),
                    ),
                  ],
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
    final name = variant.label ?? 'Standard';

    return Semantics(
      button: true,
      enabled: !soldOut,
      selected: selected,
      label: soldOut
          ? '$name, sold out'
          : '$name, ${moneySemantics(variant.priceCents)}',
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color:
                          soldOut ? AppColors.disabledText : AppColors.ink,
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
    required this.onViewCart,
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
    required this.buttonLabel,
    required this.buttonSemantics,
    required this.onAdd,
  });

  final String? addedMessage;
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
                child: message == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AddedBanner(
                          message: message,
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
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          buttonLabel,
                          maxLines: 1,
                          semanticsLabel: buttonSemantics,
                        ),
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

/// The success notice after adding: green check on green-soft, ink text
/// and an ink "View cart" link.
class _AddedBanner extends StatelessWidget {
  const _AddedBanner({required this.message, required this.onViewCart});

  final String message;
  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: const BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: AppDims.controlBorderRadius,
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 20, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              liveRegion: true,
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
