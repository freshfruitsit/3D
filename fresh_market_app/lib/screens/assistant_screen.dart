import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../assistant/assistant_brain.dart';
import '../assistant/assistant_session.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';

/// The demo shopping assistant: a chat with scripted replies (keyword
/// matching, not AI) built from the live store. Full screen, no bottom
/// bar.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, this.session});

  /// The conversation to show; the app's shared one when null.
  final AssistantSession? session;

  static const String title = 'Fresh Market Assistant';
  static const String caption = 'Demo assistant: scripted replies, not AI yet';
  static const String inputHint = 'Ask for a product or a category';

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// True while "Go to checkout" checks the cart against the store.
  bool _openingCheckout = false;

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
    // The list is reversed, so offset 0 is the newest message.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || _scroll.offset == 0) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _send(String text) {
    if (text.trim().isEmpty || _session.busy) return;
    _input.clear();
    _session.send(
      text,
      api: context.read<ShopifyApi>(),
      cart: context.read<CartStore>(),
    );
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

  void _run(AssistantAction action) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _session.messages;
    final busy = _session.busy;
    // Newest first, because the list is reversed.
    final count = messages.length + (busy ? 1 : 0);

    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(
          children: [
            const _Header(),
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
                            onAction: _run,
                          );
                  },
                ),
              ),
            ),
            _SuggestionRow(onTap: busy ? null : _send),
            _InputBar(controller: _input, enabled: !busy, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, AppDims.gutter, 8),
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

/// An assistant answer: the bubble, then its product rows and buttons.
class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({required this.reply, required this.onAction});

  final AssistantReply reply;
  final ValueChanged<AssistantAction> onAction;

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
              children: [
                for (final action in reply.actions)
                  _ActionButton(
                    label: action.label,
                    onTap: () => onAction(action),
                  ),
              ],
            ),
          ),
      ],
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

/// White pill with a green border, green text and a chevron.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.brand)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(label, style: AppText.link)),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.brand,
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

/// The ready-made questions, scrolling sideways.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.onTap});

  /// Null while a reply is loading.
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDims.touch + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        itemCount: AssistantBrain.suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final label = AssistantBrain.suggestions[index];
          return Semantics(
            button: true,
            enabled: onTap != null,
            label: 'Ask: $label',
            excludeSemantics: true,
            child: Material(
              color: AppColors.surface,
              shape: const StadiumBorder(
                side: BorderSide(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap == null ? null : () => onTap!(label),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      label,
                      style: AppText.body.copyWith(
                        color: AppColors.ink,
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

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  final TextEditingController controller;

  /// False while a reply is loading: typing still works, sending waits.
  final bool enabled;
  final ValueChanged<String> onSend;

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
            Semantics(
              button: true,
              enabled: enabled,
              label: 'Send',
              excludeSemantics: true,
              child: Tooltip(
                message: 'Send',
                child: Material(
                  color: enabled ? AppColors.brand : AppColors.disabledFill,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: enabled ? () => onSend(controller.text) : null,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: Icon(
                        Icons.arrow_upward,
                        size: 22,
                        color: enabled ? Colors.white : AppColors.disabledText,
                      ),
                    ),
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
