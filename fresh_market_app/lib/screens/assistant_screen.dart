import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../app_nav.dart';
import '../assistant/assistant_brain.dart';
import '../assistant/assistant_session.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';

/// Opens [uri] outside the app; true when something opened it.
typedef AssistantLinkLauncher = Future<bool> Function(Uri uri);

/// The demo shopping assistant: a chat with scripted replies (keyword
/// matching, not AI) built from the live store. Full screen, no bottom
/// bar.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.session, this.launcher});

  /// The conversation to show; the app's shared one when null.
  final AssistantSession? session;

  /// Opens the phone, email and store links of [OpenLinkAction]s;
  /// [launchExternally] when null. Tests pass a stub.
  final AssistantLinkLauncher? launcher;

  static const String title = 'Fresh Market Assistant';
  static const String caption = 'Demo assistant: scripted replies, not AI yet';
  static const String inputHint = 'Ask for a product or a category';

  /// Opens [uri] in the app that handles it (dialer, mail, browser).
  static Future<bool> launchExternally(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// True while "Go to checkout" checks the cart against the store.
  bool _openingCheckout = false;

  /// "Add all" and "empty my cart" buttons already carried out, with the
  /// message they belong to: a second tap does nothing.
  final Set<(AssistantMessage, AssistantAction)> _done = {};

  AssistantSession get _session => widget.session ?? AssistantSession.shared;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.session ?? AssistantSession.shared;
    if (!identical(old, _session)) {
      old.removeListener(_onSessionChanged);
      _session.addListener(_onSessionChanged);
      _done.clear();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToNewest();
  }

  /// The list is reversed, so offset 0 is the newest message.
  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset == 0) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// Sends [text] to the assistant. Only text typed in the field is
  /// cleared from it; a chip or option leaves a draft alone.
  void _send(String text, {bool fromInput = false}) {
    if (text.trim().isEmpty || _session.busy) return;
    if (fromInput) _input.clear();
    _session.send(
      text,
      api: context.read<ShopifyApi>(),
      cart: context.read<CartStore>(),
      favourites: context.read<FavouritesStore>(),
    );
  }

  void _newChat() {
    if (_session.busy) return;
    _done.clear();
    _session.reset();
  }

  /// Shows the options grid at the bottom of the conversation, unless the
  /// newest message already shows it.
  void _showOptions() {
    if (_session.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final last = _session.messages.last;
    if (last.fromUser || !last.reply!.showOptions) _session.showOptions();
    _scrollToNewest();
  }

  /// One checkout at a time, and nothing else can be opened while the
  /// cart is being checked (the list ignores taps meanwhile).
  Future<void> _openCheckout() async {
    if (_openingCheckout) return;
    if (context.read<CartStore>().isEmpty) {
      AppNav.showNotice(context, 'Your cart is empty.', bottomMargin: 12);
      return;
    }
    setState(() => _openingCheckout = true);
    try {
      await AppNav.openCheckout(context);
    } finally {
      if (mounted) setState(() => _openingCheckout = false);
    }
  }

  void _run(AssistantMessage source, AssistantAction action) {
    FocusManager.instance.primaryFocus?.unfocus();
    switch (action) {
      case OpenCartAction():
        AppNav.goToTab(context, AppTab.cart);
      case CheckoutAction():
        _openCheckout();
      case OpenCollectionAction(:final handle, :final title):
        AppNav.openCollection(context, handle: handle, title: title);
      case OpenSearchAction(:final query):
        AppNav.openSearch(context, initialQuery: query);
      case OpenCategoriesAction():
        AppNav.goToTab(context, AppTab.categories);
      case OpenFavouritesAction():
        AppNav.openFavourites(context);
      case SendMessageAction(:final message):
        _send(message);
      case AddProductsAction(:final products):
        if (_markDone(source, action)) _addAll(products);
      case ClearCartAction():
        if (_markDone(source, action)) _clearCart();
      case OpenLinkAction(:final uri):
        _openLink(uri);
    }
  }

  /// False when [action] of [source] was already carried out, or cannot
  /// be now because a reply is loading (its answer could not be added).
  bool _markDone(AssistantMessage source, AssistantAction action) {
    if (_session.busy || !_done.add((source, action))) return false;
    setState(() {});
    return true;
  }

  /// One unit of the first variant in stock of each product; sold-out
  /// products are skipped and named.
  void _addAll(List<Product> products) {
    final cart = context.read<CartStore>();
    final added = <String>[];
    final soldOut = <String>[];
    final full = <String>[];
    for (final product in products) {
      final variant = product.variants.where((v) => v.available).firstOrNull;
      if (variant == null) {
        soldOut.add(product.title);
        continue;
      }
      final name = variant.label == null
          ? product.title
          : '${product.title} (${variant.label})';
      final before = cart.quantityOf(variant.id);
      cart.add(product, variant);
      (cart.quantityOf(variant.id) > before ? added : full).add(name);
    }
    final count = added.length;
    final text = StringBuffer(
      count == 0
          ? 'Nothing was added.'
          : 'Added $count ${count == 1 ? 'product' : 'products'} to your '
              'cart: ${_joinNames(added)}.',
    );
    if (soldOut.isNotEmpty) {
      text.write(' ${_joinNames(soldOut)} '
          '${soldOut.length == 1 ? 'is' : 'are'} sold out.');
    }
    if (full.isNotEmpty) {
      text.write(' Your cart already holds the most it can of '
          '${_joinNames(full)} (${CartStore.maxQuantity}).');
    }
    _session.note(
      count == 0
          ? AssistantReply(text.toString())
          : AssistantReply(
              text.toString(),
              actions: const [OpenCartAction()],
              suggestions: const [
                'Open my cart',
                'Checkout',
                'Ideas for a smoothie',
              ],
            ),
    );
  }

  void _clearCart() {
    final cart = context.read<CartStore>();
    if (cart.isEmpty) {
      _session.note(const AssistantReply('Your cart is already empty.'));
      return;
    }
    cart.clear();
    _session.note(
      const AssistantReply(
        'Done. Your cart is empty now.',
        suggestions: [
          'What is on offer?',
          'Show me berries',
          'Ideas for a fruit salad',
        ],
      ),
    );
  }

  /// Opens a `tel:`, `mailto:` or `https:` link outside the app; any
  /// other kind is never launched. Says so when nothing opened it.
  Future<void> _openLink(String link) async {
    final launch = widget.launcher ?? AssistantScreen.launchExternally;
    final uri = Uri.tryParse(link);
    var opened = false;
    if (uri != null && _linkSchemes.contains(uri.scheme.toLowerCase())) {
      try {
        opened = await launch(uri);
      } catch (_) {
        // No app for it, or the platform refused: said below.
      }
    }
    if (opened || !mounted) return;
    AppNav.showNotice(context, _linkFailure(link), bottomMargin: 12);
  }

  @override
  Widget build(BuildContext context) {
    final messages = _session.messages;
    final busy = _session.busy;
    // Newest first, because the list is reversed.
    final count = messages.length + (busy ? 1 : 0);
    final ownSuggestions = _session.lastReply?.suggestions ?? const [];
    final suggestions = ownSuggestions.isNotEmpty
        ? ownSuggestions
        : AssistantBrain.defaultSuggestions;

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onNewChat: busy ? null : _newChat),
            const Divider(height: 1, thickness: 1, color: AppColors.border),
            if (_openingCheckout)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.brand,
                backgroundColor: AppColors.border,
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _openingCheckout,
                child: ListView.separated(
                  controller: _scroll,
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  itemCount: count,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (busy && index == 0) return const _TypingBubble();
                    final message = messages[
                        messages.length - 1 - (busy ? index - 1 : index)];
                    return message.fromUser
                        ? _UserBubble(text: message.text)
                        : _AssistantBlock(
                            reply: message.reply!,
                            busy: busy,
                            isDone: (action) =>
                                _done.contains((message, action)),
                            onAction: (action) => _run(message, action),
                            onOption: _send,
                          );
                  },
                ),
              ),
            ),
            _SuggestionRow(
              suggestions: suggestions,
              onTap: busy ? null : _send,
            ),
            _InputBar(
              controller: _input,
              enabled: !busy,
              onSend: (text) => _send(text, fromInput: true),
              onOptions: _showOptions,
            ),
          ],
        ),
      ),
    );
  }
}

/// "a", "a and b", "a, b and c".
String _joinNames(List<String> names) => names.length < 2
    ? names.join()
    : '${names.take(names.length - 1).join(', ')} and ${names.last}';

/// The only links an [OpenLinkAction] may open.
const Set<String> _linkSchemes = {'tel', 'mailto', 'https'};

String _linkScheme(String link) =>
    Uri.tryParse(link)?.scheme.toLowerCase() ?? '';

/// The number or address of a `tel:` or `mailto:` link, for saying it
/// when the link cannot be opened.
String _linkTarget(String link) {
  final path = Uri.tryParse(link)?.path ?? '';
  try {
    return Uri.decodeComponent(path).trim();
  } on ArgumentError {
    return path.trim();
  }
}

String _linkFailure(String link) {
  final target = _linkTarget(link);
  return switch (_linkScheme(link)) {
    'tel' => target.isEmpty
        ? "Couldn't open the phone app."
        : "Couldn't open the phone app. Call $target instead.",
    'mailto' => target.isEmpty
        ? "Couldn't open the email app."
        : "Couldn't open the email app. Write to $target instead.",
    'https' => "Couldn't open the store page.",
    _ => "Couldn't open that link.",
  };
}

IconData _linkIcon(String link) => switch (_linkScheme(link)) {
      'tel' => Icons.phone,
      'mailto' => Icons.mail,
      _ => Icons.open_in_new,
    };

class _Header extends StatelessWidget {
  const _Header({required this.onNewChat});

  /// Null while a reply is loading.
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 6, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(Icons.auto_awesome, size: 20, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  // Shrinks instead of being cut off with a large font.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AssistantScreen.title,
                      maxLines: 1,
                      style: AppText.cardHeading.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const Text(
                  AssistantScreen.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'New chat',
            color: AppColors.brand,
            icon: const Icon(Icons.add_comment_outlined, size: 22),
            onPressed: onNewChat,
          ),
        ],
      ),
    );
  }
}

const BorderRadius _bubbleRadius = BorderRadius.all(Radius.circular(16));

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.85,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            label: 'You said',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: AppColors.brand,
                borderRadius: _bubbleRadius,
              ),
              child: Text(
                text,
                style: AppText.body.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white bubble with the app's border, hugging its content up to 85% of
/// the width.
class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.85,
      alignment: Alignment.centerLeft,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: _bubbleRadius,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// An assistant answer: the bubble, then its product rows, its buttons
/// and, when asked for, the options grid across the full width.
class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    required this.reply,
    required this.busy,
    required this.isDone,
    required this.onAction,
    required this.onOption,
  });

  final AssistantReply reply;

  /// True while a reply is loading: buttons that talk to the assistant
  /// and the options grid wait.
  final bool busy;

  /// True for an "add all" or "empty my cart" button already carried out.
  final bool Function(AssistantAction action) isDone;
  final ValueChanged<AssistantAction> onAction;

  /// Sends an option's message.
  final ValueChanged<String> onOption;

  Widget _button(AssistantAction action) {
    final done = isDone(action);
    final talks = switch (action) {
      SendMessageAction() || AddProductsAction() || ClearCartAction() => true,
      _ => false,
    };
    final VoidCallback? onTap =
        done || (busy && talks) ? null : () => onAction(action);
    return switch (action) {
      AddProductsAction() => _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: done ? Icons.check : Icons.add_shopping_cart,
          look: _ActionLook.filled,
        ),
      ClearCartAction() => _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: done ? Icons.check : Icons.remove_shopping_cart,
          look: _ActionLook.danger,
        ),
      OpenLinkAction(:final uri) => _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: _linkIcon(uri),
        ),
      _ => _ActionButton(label: action.label, onTap: onTap),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _AssistantBubble(
          child: Text(
            reply.text,
            style: AppText.body.copyWith(fontSize: 15, color: AppColors.ink),
          ),
        ),
        if (reply.products.isNotEmpty)
          FractionallySizedBox(
            widthFactor: 0.9,
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final product in reply.products)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ProductRow(product: product),
                  ),
              ],
            ),
          ),
        if (reply.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final action in reply.actions) _button(action)],
            ),
          ),
        if (reply.showOptions)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _OptionsGrid(onSelected: busy ? null : onOption),
          ),
      ],
    );
  }
}

/// The 8 [AssistantBrain.quickOptions] in 4 columns, as mild-green tiles
/// like the category tiles. Each row is as tall as its tallest tile, so a
/// large font grows the tiles instead of cutting labels off.
class _OptionsGrid extends StatelessWidget {
  const _OptionsGrid({required this.onSelected});

  /// Receives the option's message; null while a reply is loading.
  final ValueChanged<String>? onSelected;

  static const int _columns = 4;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    const options = AssistantBrain.quickOptions;
    // Measured here: the rows below size themselves by their content,
    // which a LayoutBuilder inside them could not report.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth =
            (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
        final labelWidth = tileWidth - _OptionTile.sidePadding * 2;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0; start < options.length; start += _columns)
              Padding(
                padding: EdgeInsets.only(top: start == 0 ? 0 : _gap),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = start; i < start + _columns; i++) ...[
                        if (i > start) const SizedBox(width: _gap),
                        Expanded(
                          child: i < options.length
                              ? _OptionTile(
                                  option: options[i],
                                  labelWidth: labelWidth,
                                  onTap: onSelected == null
                                      ? null
                                      : () => onSelected!(options[i].message),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.labelWidth,
    required this.onTap,
  });

  final QuickOption option;

  /// Room for the label inside the tile's padding.
  final double labelWidth;

  /// Null: greyed and not tappable.
  final VoidCallback? onTap;

  static const double minHeight = 84;
  static const double sidePadding = 4;

  /// The label's font size: [style]'s, or smaller when the label's
  /// longest word would not fit on one line ("Categories" on a narrow
  /// phone with a large font), so no word is broken in two.
  static double fittingFontSize(
    String label,
    TextStyle style,
    TextScaler scaler,
    double width,
  ) {
    double widestWord(double fontSize) {
      var widest = 0.0;
      for (final word in label.split(' ')) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style.copyWith(fontSize: fontSize)),
          textScaler: scaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        if (painter.width > widest) widest = painter.width;
        painter.dispose();
      }
      return widest;
    }

    var fontSize = style.fontSize!;
    if (width <= 0) return fontSize;
    // A few rounds, as large-font scaling is not always linear.
    for (var round = 0; round < 4; round++) {
      final widest = widestWord(fontSize);
      if (widest <= width) break;
      fontSize = fontSize * width / widest * 0.98;
    }
    return fontSize;
  }

  static IconData iconFor(QuickOptionKind kind) => switch (kind) {
        QuickOptionKind.offers => Icons.local_offer_outlined,
        QuickOptionKind.categories => Icons.grid_view_rounded,
        QuickOptionKind.recipes => Icons.restaurant_menu,
        QuickOptionKind.local => Icons.place_outlined,
        QuickOptionKind.gifts => Icons.card_giftcard,
        QuickOptionKind.popular => Icons.trending_up,
        QuickOptionKind.cart => Icons.shopping_bag_outlined,
        QuickOptionKind.contact => Icons.support_agent,
      };

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final style = AppText.tileLabel.copyWith(
      letterSpacing: 0,
      color: enabled ? AppColors.tileLabel : AppColors.disabledText,
    );
    final fontSize = fittingFontSize(
      option.label,
      style,
      MediaQuery.textScalerOf(context),
      labelWidth,
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: option.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: enabled ? AppColors.tile : AppColors.disabledFill,
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.cardBorderRadius,
          // Subtle inner edge, as on the category tiles.
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                sidePadding,
                10,
                sidePadding,
                8,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    iconFor(option.kind),
                    size: 26,
                    color: enabled ? AppColors.brand : AppColors.disabledText,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    option.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style.copyWith(fontSize: fontSize),
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

/// Thumbnail, name with size, price and the add control. Opens the
/// product when tapped.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final variant = product.defaultVariant;
    final size = variant?.label;
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDims.cardBorderRadius,
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          AppNav.openProduct(context, product);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: ProductImage(url: product.imageUrl, logicalWidth: 52),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      size == null ? product.title : '${product.title} $size',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.productName,
                    ),
                    if (variant != null) ...[
                      const SizedBox(height: 2),
                      PriceRow(
                        priceCents: variant.priceCents,
                        oldPriceCents: variant.oldPriceCents,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AddControl(product: product, variant: variant),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ActionLook {
  /// White pill, green border and text, chevron.
  outlined,

  /// Green pill, white text ("Add all to cart").
  filled,

  /// White pill, red border and text ("Yes, empty my cart").
  danger,
}

/// A pill button under an assistant reply, at least 44 high.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.look = _ActionLook.outlined,
  });

  final String label;

  /// Null: greyed and not tappable.
  final VoidCallback? onTap;

  /// Shown before the label.
  final IconData? icon;
  final _ActionLook look;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final (Color fill, Color edge, Color ink) = !enabled
        ? (AppColors.disabledFill, AppColors.border, AppColors.disabledText)
        : switch (look) {
            _ActionLook.outlined =>
              (AppColors.surface, AppColors.brand, AppColors.brand),
            _ActionLook.filled =>
              (AppColors.brand, AppColors.brand, Colors.white),
            _ActionLook.danger =>
              (AppColors.surface, AppColors.red, AppColors.red),
          };
    final chevron = look == _ActionLook.outlined;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: StadiumBorder(side: BorderSide(color: edge)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                icon == null ? 16 : 12,
                6,
                chevron ? 10 : 16,
                6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: ink),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: AppText.link.copyWith(color: ink),
                    ),
                  ),
                  if (chevron) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, size: 20, color: ink),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three pulsing dots while a reply is loading.
class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'The assistant is typing',
      child: _AssistantBubble(
        child: SizedBox(
          height: 22,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                    child: Opacity(
                      // Each dot peaks a third of a cycle after the last.
                      opacity: 0.3 +
                          0.7 *
                              (1 -
                                  (((_controller.value - i / 3) % 1.0) * 2 - 1)
                                      .abs()),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(width: 8, height: 8),
                      ),
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

/// Follow-up questions for the latest reply, scrolling sideways. Goes
/// back to the first chip whenever the questions change.
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({required this.suggestions, required this.onTap});

  final List<String> suggestions;

  /// Null while a reply is loading.
  final ValueChanged<String>? onTap;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_SuggestionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (listEquals(oldWidget.suggestions, widget.suggestions)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset == 0) return;
      _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final suggestions = widget.suggestions;
    return SizedBox(
      height: AppDims.touch + 12,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = suggestions[index];
          final VoidCallback? tap = onTap == null ? null : () => onTap(label);
          return Semantics(
            button: true,
            enabled: tap != null,
            label: 'Ask: $label',
            onTap: tap,
            excludeSemantics: true,
            child: Material(
              color: AppColors.surface,
              shape: const StadiumBorder(
                side: BorderSide(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppText.body.copyWith(
                        color: tap == null
                            ? AppColors.disabledText
                            : AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A round icon button with a tooltip, labelled for screen readers.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.size,
    required this.fill,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final double size;
  final Color fill;
  final Color iconColor;

  /// Null: greyed and not tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: Material(
          color: enabled ? fill : AppColors.disabledFill,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: 22,
                color: enabled ? iconColor : AppColors.disabledText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onOptions,
  });

  final TextEditingController controller;

  /// False while a reply is loading: typing still works, sending and the
  /// options button wait.
  final bool enabled;
  final ValueChanged<String> onSend;

  /// Shows the options grid again.
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(24)),
      borderSide: BorderSide.none,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            _RoundButton(
              label: 'Show options',
              icon: Icons.apps,
              size: AppDims.touch,
              fill: AppColors.tile,
              iconColor: AppColors.brand,
              onTap: enabled ? onOptions : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: onSend,
                style: AppText.body.copyWith(
                  fontSize: 15,
                  color: AppColors.ink,
                ),
                decoration: const InputDecoration(
                  hintText: AssistantScreen.inputHint,
                  hintMaxLines: 2,
                  fillColor: AppColors.page,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 13,
                  ),
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldBorder,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _RoundButton(
              label: 'Send',
              icon: Icons.arrow_upward,
              size: 46,
              fill: AppColors.brand,
              iconColor: Colors.white,
              onTap: enabled ? () => onSend(controller.text) : null,
            ),
          ],
        ),
      ),
    );
  }
}
