import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../delivery/delivery.dart';
import '../models/product.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';

/// The Express collection the delivery bar's "Shop Express items" opens.
abstract final class ExpressCollection {
  static const String handle = 'express';
  static const String title = '1Hr Express';
}

/// Text parts of the website's delivery texts, bold where it uses `<b>`.
TextSpan _spans(List<DeliveryTextPart> parts) => TextSpan(
  children: [
    for (final p in parts)
      TextSpan(
        text: p.text,
        style: p.bold ? const TextStyle(fontWeight: FontWeight.w800) : null,
      ),
  ],
);

/// The Home header's location chip: pin, "Deliver to", the area (or
/// "Choose your area") and a chevron. Opens the location picker.
class LocationChip extends StatelessWidget {
  const LocationChip({super.key});

  @override
  Widget build(BuildContext context) {
    final area = context.select<DeliveryStore, DeliveryArea?>((s) => s.area);
    final label = DeliveryCopy.chipLabel(area);
    return Semantics(
      button: true,
      label: area == null
          ? 'Choose your delivery area'
          : '${DeliveryCopy.chipHint(area)}. Change delivery location',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('location-chip'),
          borderRadius: AppDims.controlBorderRadius,
          onTap: () => AppNav.openLocationPicker(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    size: 22,
                    color: AppColors.olive,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Deliver to', style: AppText.caption),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.cardHeading.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.expand_more,
                              size: 20,
                              color: AppColors.ink,
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
      ),
    );
  }
}

/// The website's two delivery modes side by side: "Fresh Market" (full
/// range) and "Express" (selected items in under an hour), each with its
/// current promise underneath.
class DeliveryModeSwitch extends StatelessWidget {
  const DeliveryModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final area = store.area;
    final now = store.now();
    final mode = store.mode;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.page,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ModeButton(
                key: const ValueKey('mode-market'),
                icon: Icons.storefront,
                title: DeliveryMode.market.label,
                subtitle: DeliveryCopy.modeSubtitle(
                  DeliveryMode.market,
                  area,
                  now,
                ),
                selected: mode == DeliveryMode.market,
                off: false,
                onTap: () =>
                    AppNav.chooseDeliveryMode(context, DeliveryMode.market),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _ModeButton(
                key: const ValueKey('mode-express'),
                icon: Icons.bolt,
                title: DeliveryMode.express.label,
                subtitle: DeliveryCopy.modeSubtitle(
                  DeliveryMode.express,
                  area,
                  now,
                ),
                selected: mode == DeliveryMode.express,
                off: DeliveryCopy.expressOff(area),
                onTap: () =>
                    AppNav.chooseDeliveryMode(context, DeliveryMode.express),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.off,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  /// Express outside the Express zone: drawn as unavailable (a tap still
  /// says why).
  final bool off;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final titleColor = off ? AppColors.secondary : AppColors.ink;
    final subColor = selected ? AppColors.ink : AppColors.secondary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title delivery, $subtitle',
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.lime : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppDims.controlBorderRadius,
          side: BorderSide(
            color: selected ? AppColors.ink : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Row(
                children: [
                  Icon(
                    off ? Icons.block : icon,
                    size: 20,
                    color: off ? AppColors.secondary : AppColors.ink,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.productName.copyWith(
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: subColor,
                          ),
                        ),
                      ],
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

/// The website's delivery bar: the promise for the chosen area and mode,
/// how long same-day ordering stays open, and the button the website
/// offers (Express, back to Fresh Market, or set a location). In Express
/// mode it also offers "Shop Express items". Pass [product] on a product
/// page.
class DeliveryBarView extends StatelessWidget {
  const DeliveryBarView({super.key, this.product, this.noticeBottomMargin});

  final Product? product;

  /// See [AppNav.showNotice].
  final double? noticeBottomMargin;

  static const String shopExpress = 'Shop Express items';

  void _run(BuildContext context, DeliveryBarAction action) {
    switch (action) {
      case DeliveryBarAction.setLocation:
        AppNav.openLocationPicker(
          context,
          noticeBottomMargin: noticeBottomMargin,
        );
      case DeliveryBarAction.market:
        AppNav.chooseDeliveryMode(
          context,
          DeliveryMode.market,
          noticeBottomMargin: noticeBottomMargin,
        );
      case DeliveryBarAction.express:
        AppNav.chooseDeliveryMode(
          context,
          DeliveryMode.express,
          noticeBottomMargin: noticeBottomMargin,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final bar = DeliveryCopy.bar(
      area: store.area,
      mode: store.mode,
      now: store.now(),
      product: product,
    );
    final expressMode = store.isExpress && store.hasArea;
    final IconData icon = switch (bar.kind) {
      DeliveryBarKind.askLocation => Icons.location_on_outlined,
      DeliveryBarKind.notOnExpress ||
      DeliveryBarKind.expressClosed => Icons.info_outline,
      DeliveryBarKind.express => Icons.bolt,
      DeliveryBarKind.marketToday ||
      DeliveryBarKind.marketTomorrow => Icons.local_shipping_outlined,
    };
    final label = bar.actionLabel;
    final action = bar.action;
    final counter = bar.counter;

    return Container(
      key: const ValueKey('delivery-bar'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: bar.warn ? AppColors.tile : AppColors.surface,
        borderRadius: AppDims.cardBorderRadius,
        border: Border.all(color: bar.warn ? AppColors.ink : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: bar.warn ? AppColors.ink : AppColors.olive,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text.rich(
                    _spans(bar.message),
                    style: AppText.body.copyWith(color: AppColors.ink),
                  ),
                ),
              ),
            ],
          ),
          if (counter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 2),
              child: Text.rich(_spans(counter), style: AppText.caption),
            ),
          if (label != null || expressMode)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (label != null && action != null)
                    _BarButton(
                      label: label,
                      icon: switch (action) {
                        DeliveryBarAction.setLocation => Icons.location_on,
                        DeliveryBarAction.market => Icons.storefront,
                        DeliveryBarAction.express => Icons.bolt,
                      },
                      onTap: () => _run(context, action),
                    ),
                  if (expressMode && product == null)
                    TextButton(
                      onPressed: () => AppNav.openCollection(
                        context,
                        handle: ExpressCollection.handle,
                        title: ExpressCollection.title,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(shopExpress),
                          Icon(Icons.chevron_right, size: 20),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Lime pill with ink text: the delivery bar's button.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.lime,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: AppColors.ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: AppText.link.copyWith(
                        fontSize: 13.5,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
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

/// The small delivery line of a product card ("Within 6 hrs · or 30 min",
/// "25–35 min", "Fresh Market · Tomorrow by 11 AM"); nothing until a
/// delivery area is set.
class DeliveryPromiseLine extends StatelessWidget {
  const DeliveryPromiseLine({super.key, required this.product});

  final Product product;

  /// Lines the card keeps room for.
  static const int maxLines = 2;
  static const double fontSize = 11.5;
  static const double lineHeight = 1.3;

  @override
  Widget build(BuildContext context) {
    final promise = context.watch<DeliveryStore?>()?.promiseFor(product);
    if (promise == null) return const SizedBox.shrink();
    final IconData icon = switch (promise.kind) {
      ProductPromiseKind.express => Icons.bolt,
      ProductPromiseKind.market => Icons.local_shipping_outlined,
      ProductPromiseKind.marketOnly => Icons.storefront_outlined,
    };
    final text = promise.text;
    final highlight = promise.highlight;
    final at = highlight == null ? -1 : text.indexOf(highlight);
    const style = TextStyle(
      fontFamily: AppText.family,
      fontSize: fontSize,
      height: lineHeight,
      fontWeight: FontWeight.w600,
      color: AppColors.secondary,
    );
    const bold = TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink);
    return Padding(
      key: const ValueKey('promise-line'),
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 14,
              color: promise.isExpress ? AppColors.ink : AppColors.olive,
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: Text.rich(
              at < 0
                  ? TextSpan(text: text, style: promise.isExpress ? bold : null)
                  : TextSpan(
                      children: [
                        TextSpan(text: text.substring(0, at)),
                        // Non-breaking spaces keep "or 35 min" on one
                        // line when the promise wraps.
                        TextSpan(
                          text: highlight!.replaceAll(' ', '\u00A0'),
                          style: bold,
                        ),
                        TextSpan(text: text.substring(at + highlight.length)),
                      ],
                    ),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

/// Product detail's delivery box: when this item reaches the chosen area
/// by Fresh Market and, for an Express item, by Express; in Express mode
/// an item that is not on Express says so and offers Fresh Market.
class ProductDeliveryInfo extends StatelessWidget {
  const ProductDeliveryInfo({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final area = store.area;
    final now = store.now();

    Widget row(IconData icon, String text, {bool strong = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: strong ? AppColors.ink : AppColors.olive),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.body.copyWith(
                color: AppColors.ink,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    final List<Widget> rows;
    Widget? footer;
    if (area == null) {
      rows = [
        row(
          Icons.location_on_outlined,
          'Set your delivery location to see when this arrives.',
        ),
      ];
      footer = TextButton(
        onPressed: () =>
            AppNav.openLocationPicker(context, noticeBottomMargin: 150),
        child: const Text('Set location'),
      );
    } else {
      final eligible = store.isExpressEligible(product);
      final marketLine = DeliveryCopy.productMarketLine(area, now);
      final expressLine = DeliveryCopy.productExpressLine(area, now);
      if (store.isExpress && !eligible) {
        final bar = DeliveryCopy.bar(
          area: area,
          mode: store.mode,
          now: now,
          product: product,
        );
        rows = [row(Icons.info_outline, bar.text, strong: true)];
        footer = TextButton(
          onPressed: () => AppNav.chooseDeliveryMode(
            context,
            DeliveryMode.market,
            noticeBottomMargin: 150,
          ),
          child: Text(bar.actionLabel ?? 'Switch to Fresh Market'),
        );
      } else if (store.isExpress) {
        rows = [
          row(Icons.bolt, expressLine, strong: true),
          row(Icons.local_shipping_outlined, marketLine),
        ];
      } else {
        rows = [
          row(Icons.local_shipping_outlined, marketLine, strong: true),
          if (eligible) row(Icons.bolt, 'Express: $expressLine'),
        ];
      }
    }

    return Container(
      key: const ValueKey('product-delivery'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
      decoration: AppDecor.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
          ),
          Row(
            children: [
              if (area != null)
                Expanded(
                  child: Text(
                    DeliveryCopy.chipHint(area),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                )
              else
                const Spacer(),
              ?footer,
              if (area != null && footer == null)
                TextButton(
                  onPressed: () => AppNav.openLocationPicker(
                    context,
                    noticeBottomMargin: 150,
                  ),
                  child: const Text('Change'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The delivery card at the top of the cart: mode, place and promise with
/// a "Change" link, and in Express mode a note about items that are not
/// on Express.
class CartDeliveryCard extends StatelessWidget {
  const CartDeliveryCard({super.key});

  /// "2 items aren't on Express. They come with Fresh Market: Today within
  /// 6 hours."
  static String notOnExpress(int units, MarketPromise market) => units == 1
      ? "1 item isn't on Express. It comes with Fresh Market: ${market.line}."
      : "$units items aren't on Express. They come with Fresh Market: "
            '${market.line}.';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final split = context.select<CartStore, ({int express, int other})>(
      (c) => c.expressSplit,
    );
    final area = store.area;
    void change() => AppNav.openLocationPicker(context);

    if (area == null) {
      return _card(
        icon: Icons.location_on_outlined,
        title: 'Where should we deliver?',
        lines: const ['Set your location to see delivery times.'],
        action: TextButton(
          onPressed: change,
          child: const Text('Set location'),
        ),
      );
    }

    final market = store.market!;
    final express = store.express!;
    final String promise;
    if (store.isExpress) {
      promise = store.expressClosedNotice ?? 'Express in ${express.range}';
    } else {
      // A non-breaking space keeps "7:45 PM" from splitting across lines.
      final by = market.by;
      promise = market.today && by != null
          ? '${market.line} · by ${by.replaceAll(' ', '\u00A0')}'
          : market.line;
    }
    final mismatch = store.isExpress && split.other > 0
        ? notOnExpress(split.other, market)
        : null;

    return _card(
      icon: store.isExpress ? Icons.bolt : Icons.local_shipping_outlined,
      title: '${store.mode.label} delivery',
      lines: [area.label, promise],
      action: TextButton(onPressed: change, child: const Text('Change')),
      note: mismatch,
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required List<String> lines,
    required Widget action,
    String? note,
  }) {
    return Container(
      key: const ValueKey('cart-delivery'),
      decoration: AppDecor.card,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: AppColors.lime,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: AppColors.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.cardHeading),
                    for (final line in lines)
                      Text(
                        line,
                        style: AppText.body.copyWith(
                          color: line == lines.first
                              ? AppColors.ink
                              : AppColors.body,
                        ),
                      ),
                  ],
                ),
              ),
              action,
            ],
          ),
          if (note != null)
            Container(
              margin: const EdgeInsets.fromLTRB(0, 8, 8, 0),
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.tile,
                borderRadius: AppDims.controlBorderRadius,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.ink,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note,
                      style: AppText.body.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
