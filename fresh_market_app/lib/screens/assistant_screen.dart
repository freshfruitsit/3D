import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app.dart';
import '../app_nav.dart';
import '../assistant/assistant_brain.dart';
import '../assistant/assistant_session.dart';
import '../delivery/delivery.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart' as a11y;
import '../widgets/add_control.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/delivery_widgets.dart' show ExpressCollection;
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

  /// True while a phone, email or store link is being opened: a double
  /// tap opens it once.
  bool _launching = false;

  /// How many messages there were when the screen last looked, to tell
  /// screen readers about a new answer.
  late int _seenMessages;

  AssistantSession get _session => widget.session ?? AssistantSession.shared;

  @override
  void initState() {
    super.initState();
    _seenMessages = _session.messages.length;
    _session.addListener(_onSessionChanged);
  }

  @override
  void didUpdateWidget(AssistantScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.session ?? AssistantSession.shared;
    if (!identical(old, _session)) {
      old.removeListener(_onSessionChanged);
      _session.addListener(_onSessionChanged);
      _seenMessages = _session.messages.length;
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
    _announceNewAnswer();
  }

  /// Screen readers say a new answer (focus stays on what was tapped, so
  /// it would go unnoticed), with how many product rows came with it.
  void _announceNewAnswer() {
    final messages = _session.messages;
    final grew = messages.length > _seenMessages;
    _seenMessages = messages.length;
    final last = messages.last;
    if (!grew || last.fromUser) return;
    final rows = last.reply!.products.length;
    final said = spokenMoney(last.text);
    final text = switch (rows) {
      0 => said,
      1 => '$said 1 product below.',
      _ => '$said $rows products below.',
    };
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
    );
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
    if (text.trim().isEmpty) return;
    if (_session.busy) {
      // The keyboard's Send key cannot be greyed out like the button.
      if (fromInput) {
        AppNav.showNotice(
          context,
          'One moment, I am still answering.',
          bottomMargin: 12,
        );
      }
      return;
    }
    if (fromInput) _input.clear();
    _session.send(
      text,
      api: context.read<ShopifyApi>(),
      cart: context.read<CartStore>(),
      favourites: context.read<FavouritesStore>(),
      delivery: context.read<DeliveryStore?>(),
    );
  }

  void _newChat() {
    if (_session.busy) return;
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
      await AppNav.openCheckout(context, noticeBottomMargin: 12);
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
        if (_session.markDone(source, action)) _addAll(products);
      case ClearCartAction():
        _clearCart(source, action);
      case OpenLinkAction(:final uri):
        _openLink(uri);
      case ChangeLocationAction():
        _changeLocation();
    }
  }

  /// The location picker; once a place is chosen, the delivery answer for
  /// it follows in the conversation.
  Future<void> _changeLocation() async {
    final picked = await AppNav.openLocationPicker(
      context,
      noticeBottomMargin: 12,
    );
    if (!picked || !mounted) return;
    final reply = AssistantBrain(
      api: context.read<ShopifyApi>(),
      cart: context.read<CartStore>(),
      delivery: context.read<DeliveryStore?>(),
    ).deliveryReply();
    _session.note(reply);
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

  /// Empties the cart only while it holds what the shopper confirmed
  /// removing: items added since then were never confirmed.
  void _clearCart(AssistantMessage source, ClearCartAction action) {
    if (_session.busy || _session.isDone(source, action)) return;
    final cart = context.read<CartStore>();
    if (cart.isNotEmpty && !action.matches(cart)) {
      // Not marked done: asking again gives a new, current question.
      _session.note(
        const AssistantReply(
          'Your cart changed since you asked, so I left it as it is. Ask '
          '"Empty my cart" again if you still want it empty.',
          suggestions: ['Empty my cart', 'Open my cart', 'Checkout'],
        ),
      );
      return;
    }
    if (!_session.markDone(source, action)) return;
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
    if (_launching) return;
    final launch = widget.launcher ?? AssistantScreen.launchExternally;
    final uri = Uri.tryParse(link);
    var opened = false;
    if (uri != null && _linkSchemes.contains(uri.scheme.toLowerCase())) {
      _launching = true;
      try {
        opened = await launch(uri);
      } catch (_) {
        // No app for it, or the platform refused: said below.
      } finally {
        _launching = false;
      }
    }
    if (opened || !mounted) return;
    AppNav.showNotice(context, linkFailureMessage(link), bottomMargin: 12);
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
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _Header(onNewChat: busy ? null : _newChat),
            const Divider(height: 1, thickness: 1, color: AppColors.hairline),
            if (_openingCheckout)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.ink,
                backgroundColor: AppColors.hairline,
              ),
            Expanded(
              child: AbsorbPointer(
                absorbing: _openingCheckout,
                child: ListView.separated(
                  controller: _scroll,
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    16,
                    AppDims.gutter,
                    16,
                  ),
                  itemCount: count,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: _messageGap),
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
                                _session.isDone(message, action),
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

/// Space between two messages.
const double _messageGap = 16;

/// [text] as a screen reader should say it: the Dirham sign (which voices
/// do not know) read as "AED", the way [moneySemantics] says a price.
String spokenMoney(String text) => text.contains(dirhamSign)
    ? text.replaceAll(RegExp('$dirhamSign[ $moneySpace]?'), 'AED ')
    : text;

/// [text] with a no-break space after each Dirham sign, so a sentence
/// never wraps between the sign and its amount ([formatMoney] already
/// writes one; this also covers a plain space typed elsewhere).
String keepMoneyTogether(String text) =>
    text.replaceAll('$dirhamSign ', '$dirhamSign$moneySpace');

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

/// What to say when [link] (a `tel:`, `mailto:` or store link) could not
/// be opened: the number or address to use instead.
String linkFailureMessage(String link) {
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
      padding: const EdgeInsets.fromLTRB(AppDims.gutter, 8, AppDims.gutter, 12),
      child: Row(
        children: [
          CircleIconButton.back(context),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              // Shrinks instead of being cut off with a large font.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  AssistantScreen.title,
                  maxLines: 1,
                  style: AppText.heading,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          CircleIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: 'New chat',
            iconColor:
                onNewChat == null ? AppColors.disabledText : AppColors.ink,
            onPressed: onNewChat,
          ),
        ],
      ),
    );
  }
}

/// Bubbles are rounded, with a tighter corner on the speaker's side at the
/// top, where the message starts.
const Radius _bubbleCorner = Radius.circular(18);
const Radius _bubbleTail = Radius.circular(6);

/// The shopper's message: ink with white text, on the right.
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
                color: AppColors.ink,
                borderRadius: BorderRadius.only(
                  topLeft: _bubbleCorner,
                  topRight: _bubbleTail,
                  bottomLeft: _bubbleCorner,
                  bottomRight: _bubbleCorner,
                ),
              ),
              child: Text(
                text,
                semanticsLabel: spokenMoney(text),
                style: AppText.body.copyWith(color: AppColors.onDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The assistant's words: an off-white bubble on the left, hugging its
/// content up to 85% of the width.
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
            color: AppColors.subtle,
            borderRadius: BorderRadius.only(
              topLeft: _bubbleTail,
              topRight: _bubbleCorner,
              bottomLeft: _bubbleCorner,
              bottomRight: _bubbleCorner,
            ),
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
      SendMessageAction() ||
      AddProductsAction() ||
      ClearCartAction() ||
      ChangeLocationAction() => true,
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
          done: done,
        ),
      ClearCartAction() => _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: done ? Icons.check : Icons.remove_shopping_cart,
          look: _ActionLook.danger,
          done: done,
        ),
      OpenLinkAction(:final uri) => _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: _linkIcon(uri),
        ),
      ChangeLocationAction() => _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: Icons.location_on_outlined,
        ),
      // Express is the one place green marks a non-buying button.
      OpenCollectionAction(:final handle)
          when handle == ExpressCollection.handle =>
        _ActionButton(
          label: action.label,
          onTap: onTap,
          icon: Icons.bolt,
          iconColor: AppColors.green,
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
            keepMoneyTogether(reply.text),
            // Prices are heard as "AED 12.50", like everywhere else.
            semanticsLabel: spokenMoney(reply.text),
            style: AppText.body,
          ),
        ),
        // Product rows use the full width, like the options grid: room
        // for the name next to the add control.
        for (final product in reply.products)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ProductRow(product: product),
          ),
        if (reply.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final action in reply.actions) _button(action)],
            ),
          ),
        if (reply.showOptions)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _OptionsGrid(onSelected: busy ? null : onOption),
          ),
      ],
    );
  }
}

/// The 8 [AssistantBrain.quickOptions] in 4 columns, as off-white tiles
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
  ) => a11y.fittingFontSize(label, style, scaler, width);

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
      color: enabled ? AppColors.ink : AppColors.disabledText,
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
        // Off-white squares like the category tiles, no border. While a
        // reply loads only the icon and label grey out: the grid does not
        // flash darker with every question.
        color: AppColors.subtle,
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.cardBorderRadius,
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
                    size: 24,
                    color: enabled ? AppColors.ink : AppColors.disabledText,
                  ),
                  const SizedBox(height: 8),
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

/// A white card with a hairline: the photo in an off-white well, name,
/// size, price and the green add control. Opens the product when tapped.
class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product});

  final Product product;

  static const double thumbSize = 60;

  @override
  Widget build(BuildContext context) {
    final variant = product.defaultVariant;
    final size = product.sizeText(variant);
    return DecoratedBox(
      decoration: const ShapeDecoration(
        shape: AppDecor.cardShape,
        shadows: AppShadows.card,
      ),
      child: Material(
        color: AppColors.surface,
        shape: AppDecor.cardShape,
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
                DecoratedBox(
                  decoration: AppDecor.well,
                  child: SizedBox(
                    width: thumbSize,
                    height: thumbSize,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ProductImage(
                        url: product.imageUrl,
                        logicalWidth: thumbSize,
                        wellColor: AppColors.subtle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.productName,
                      ),
                      if (size != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          size,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption,
                        ),
                      ],
                      if (variant != null) ...[
                        const SizedBox(height: 4),
                        PriceRow(
                          priceCents: variant.priceCents,
                          oldPriceCents: variant.oldPriceCents,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // The "Removed … Undo" notice sits where the assistant's
                // other notices do.
                AddControl(
                  product: product,
                  variant: variant,
                  noticeBottomMargin: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ActionLook {
  /// White pill, ink border and text, chevron.
  outlined,

  /// Green pill, white text ("Add all to cart").
  filled,

  /// White pill, ink border and text ("Yes, empty my cart").
  danger,
}

/// A pill button under an assistant reply, at least 44 high.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.look = _ActionLook.outlined,
    this.done = false,
  });

  final String label;

  /// Null: greyed and not tappable.
  final VoidCallback? onTap;

  /// Shown before the label.
  final IconData? icon;

  /// The icon's colour while enabled; the label's colour when null.
  final Color? iconColor;
  final _ActionLook look;

  /// Already carried out: screen readers hear so, not just "disabled".
  final bool done;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final (Color fill, Color edge, Color ink) = !enabled
        ? (AppColors.disabledFill, AppColors.hairline, AppColors.disabledText)
        : switch (look) {
            _ActionLook.outlined =>
              (AppColors.surface, AppColors.ink, AppColors.ink),
            _ActionLook.filled =>
              (AppColors.green, AppColors.green, AppColors.onDark),
            _ActionLook.danger =>
              (AppColors.surface, AppColors.ink, AppColors.ink),
          };
    final chevron = look == _ActionLook.outlined;
    // The ink outline is 1.5px, like the app's outlined buttons.
    final edgeWidth = enabled && look != _ActionLook.filled ? 1.5 : 1.0;
    return Semantics(
      // Its own node even when disabled, so it is not read together with
      // the reply above it.
      container: true,
      button: true,
      enabled: enabled,
      label: done ? '$label, done' : label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: StadiumBorder(side: BorderSide(color: edge, width: edgeWidth)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                icon == null ? 16 : 14,
                6,
                chevron ? 10 : 16,
                6,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: enabled ? iconColor ?? ink : ink,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: AppText.buttonSmall.copyWith(color: ink),
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
        padding: const EdgeInsets.fromLTRB(
          AppDims.gutter,
          4,
          AppDims.gutter,
          8,
        ),
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
                side: BorderSide(color: AppColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppText.buttonSmall.copyWith(
                        color: tap == null
                            ? AppColors.disabledText
                            : AppColors.ink,
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

/// A round icon button with a tooltip, labelled for screen readers: a
/// [diameter] circle centred in a 44px touch target.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.fill,
    required this.iconColor,
    required this.onTap,
    this.diameter = size,
    this.disabledFill = AppColors.disabledFill,
  });

  final String label;
  final IconData icon;
  final Color fill;
  final Color iconColor;

  /// The visible circle, at most [size].
  final double diameter;

  /// The fill while [onTap] is null.
  final Color disabledFill;

  /// Null: greyed and not tappable.
  final VoidCallback? onTap;

  /// The touch target.
  static const double size = AppDims.touch;

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
        child: InkResponse(
          onTap: onTap,
          radius: size / 2,
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: enabled ? fill : disabledFill,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: Icon(
                    icon,
                    size: 22,
                    color: enabled ? iconColor : AppColors.disabledText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The composer: one off-white pill holding the options button, the text
/// field and the ink Send button, with the demo label under it.
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

  /// The ink circle of the Send button, inside the 48px pill.
  static const double sendDiameter = 36;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: AppDecor.stickyBar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A Material, so the buttons' ripples show on the pill.
            Material(
              color: AppColors.subtle,
              shape: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Row(
                  children: [
                    _RoundButton(
                      label: 'Show options',
                      icon: Icons.apps,
                      fill: Colors.transparent,
                      disabledFill: Colors.transparent,
                      iconColor: AppColors.ink,
                      onTap: enabled ? onOptions : null,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        textInputAction: TextInputAction.send,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: onSend,
                        // Keeps the keyboard up after sending, for a
                        // follow-up question.
                        onEditingComplete: () {},
                        style: AppText.body,
                        decoration: const InputDecoration(
                          hintText: AssistantScreen.inputHint,
                          hintMaxLines: 2,
                          // The pill around it is the field.
                          filled: false,
                          isDense: true,
                          // The buttons' own padding is the gap on either
                          // side.
                          contentPadding: EdgeInsets.symmetric(vertical: 13),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    _RoundButton(
                      label: 'Send',
                      icon: Icons.arrow_upward,
                      diameter: sendDiameter,
                      fill: AppColors.ink,
                      iconColor: AppColors.onDark,
                      onTap: enabled ? () => onSend(controller.text) : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // Never cut off: the label must stay readable at any font size,
            // so it wraps to as many lines as it needs.
            const Text(
              AssistantScreen.caption,
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}
