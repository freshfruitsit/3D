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

/// The Home header's location chip, for the right end of the header:
/// "Deliver to" and a chevron, then a green pin and the area name (or
/// "Choose your area"), right-aligned and ellipsized. It never takes more
/// than [maxWidthFraction] of the screen width. Opens the location picker.
class LocationChip extends StatelessWidget {
  const LocationChip({super.key, this.maxWidthFraction = 0.55});

  /// Widest it may be, as a share of the screen width.
  final double maxWidthFraction;

  @override
  Widget build(BuildContext context) {
    final area = context.select<DeliveryStore, DeliveryArea?>((s) => s.area);
    final label = DeliveryCopy.chipLabel(area);
    final maxWidth = MediaQuery.sizeOf(context).width * maxWidthFraction;
    return Semantics(
      button: true,
      label: area == null
          ? 'Choose your delivery area'
          : '${DeliveryCopy.chipHint(area)}. Change delivery location',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const ValueKey('location-chip'),
            borderRadius: AppDims.controlBorderRadius,
            onTap: () => AppNav.openLocationPicker(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppDims.touch),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Deliver to', style: AppText.caption),
                        SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppColors.secondary,
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 16,
                          color: AppColors.green,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.productName.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The website's two delivery modes as a segmented control: an off-white
/// track with the chosen segment raised in white. "Fresh Market"
/// (storefront, its slot underneath) and "Express" (green bolt; its time
/// in green when Express can deliver now, grey "Not in your area" /
/// "Opens 8 AM" otherwise).
class DeliveryModeSwitch extends StatelessWidget {
  const DeliveryModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final area = store.area;
    final now = store.now();
    final mode = store.mode;
    final expressOff = DeliveryCopy.expressOff(area);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: AppColors.subtle,
        borderRadius: AppDims.cardBorderRadius,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ModeSegment(
                key: const ValueKey('mode-market'),
                icon: Icons.storefront,
                iconColor: AppColors.ink,
                title: DeliveryMode.market.label,
                subtitle: DeliveryCopy.modeSubtitle(
                  DeliveryMode.market,
                  area,
                  now,
                ),
                subtitleColor: AppColors.secondary,
                selected: mode == DeliveryMode.market,
                off: false,
                onTap: () =>
                    AppNav.chooseDeliveryMode(context, DeliveryMode.market),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _ModeSegment(
                key: const ValueKey('mode-express'),
                icon: Icons.bolt,
                iconColor: expressOff ? AppColors.tertiary : AppColors.green,
                title: DeliveryMode.express.label,
                subtitle: DeliveryCopy.modeSubtitle(
                  DeliveryMode.express,
                  area,
                  now,
                ),
                subtitleColor: DeliveryCopy.expressLive(area, now)
                    ? AppColors.green
                    : AppColors.secondary,
                selected: mode == DeliveryMode.express,
                off: expressOff,
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

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.subtitleColor,
    required this.selected,
    required this.off,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final bool selected;

  /// Express outside the Express zone: drawn as unavailable (a tap still
  /// says why).
  final bool off;
  final VoidCallback onTap;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$title delivery, $subtitle',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected ? AppColors.surface : const Color(0x00FFFFFF),
          borderRadius: _radius,
          boxShadow: selected ? AppShadows.raised : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: _radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: iconColor),
                    const SizedBox(width: 8),
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
                              fontWeight: FontWeight.w700,
                              color: off ? AppColors.secondary : AppColors.ink,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: subtitleColor,
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
      ),
    );
  }
}

/// The Home header's compact delivery line (no card): an icon, the
/// promise for the chosen area and mode with its key time in bold, and on
/// the right a small text button when one applies.
///
/// * No area: the website's "Tell us where you are …" with "Set location".
/// * Fresh Market before the cut-off: "**Today by 4 PM** · order within
///   8h 0m"; after it: "**Tomorrow by 11 AM** · same-day orders closed at
///   6 PM". When Express can deliver now, a green "Express 30–40 min ›"
///   switches to Express.
/// * Express, open: green bolt, "**30–40 min** · open until 10 PM" and a
///   green "Shop Express ›" that opens the Express collection.
/// * Express, closed: "**Express is closed right now.** Opens 8 AM" and
///   "Fresh Market ›" to switch back.
///
/// Every time and place comes from the delivery rules ([DeliveryStore]).
class DeliveryLine extends StatelessWidget {
  const DeliveryLine({super.key, this.noticeBottomMargin});

  /// See [AppNav.showNotice].
  final double? noticeBottomMargin;

  static const String setLocation = 'Set location';
  static const String shopExpress = 'Shop Express';
  static const String backToMarket = 'Fresh Market';

  /// The label of the switch-to-Express button: "Express 30–40 min".
  static String expressLabel(String range) => 'Express $range';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final area = store.area;
    const b = DeliveryTextPart.new;

    final IconData icon;
    Color iconColor = AppColors.ink;
    final List<DeliveryTextPart> parts;
    Color boldColor = AppColors.ink;
    String? actionLabel;
    bool actionGreen = false;
    VoidCallback? action;

    if (area == null) {
      icon = Icons.location_on_outlined;
      parts = DeliveryCopy.bar(
        area: null,
        mode: store.mode,
        now: store.now(),
      ).message;
      actionLabel = setLocation;
      action = () => AppNav.openLocationPicker(
            context,
            noticeBottomMargin: noticeBottomMargin,
          );
    } else if (store.isExpress) {
      final ex = store.express!;
      if (ex.open) {
        icon = Icons.bolt;
        iconColor = AppColors.green;
        boldColor = AppColors.green;
        parts = [
          b(ex.range, bold: true),
          b(' · open until '
              '${DeliveryRules.formatHour(DeliveryConfig.expressClose)}'),
        ];
        actionLabel = shopExpress;
        actionGreen = true;
        action = () => AppNav.openCollection(
              context,
              handle: ExpressCollection.handle,
              title: ExpressCollection.title,
            );
      } else {
        icon = Icons.schedule;
        parts = [
          b('Express is closed right now.', bold: true),
          b(' Opens '
              '${DeliveryRules.formatHour(DeliveryConfig.expressOpen)}'),
        ];
        actionLabel = backToMarket;
        action = () => AppNav.chooseDeliveryMode(
              context,
              DeliveryMode.market,
              noticeBottomMargin: noticeBottomMargin,
            );
      }
    } else {
      final mk = store.market!;
      final ex = store.express!;
      icon = Icons.local_shipping_outlined;
      parts = [
        b(mk.slot, bold: true),
        if (mk.today)
          b(' · order within ${mk.left}')
        else
          b(' · same-day orders closed at '
              '${DeliveryRules.formatHour(mk.cutHour)}'),
      ];
      if (ex.available) {
        actionLabel = expressLabel(ex.range);
        actionGreen = true;
        action = () => AppNav.chooseDeliveryMode(
              context,
              DeliveryMode.express,
              noticeBottomMargin: noticeBottomMargin,
            );
      }
    }

    final text = Text.rich(
      TextSpan(
        children: [
          for (final p in parts)
            TextSpan(
              text: p.text,
              style: p.bold
                  ? TextStyle(fontWeight: FontWeight.w700, color: boldColor)
                  : null,
            ),
        ],
      ),
      style: AppText.bodySmall.copyWith(
        fontSize: 13,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: AppColors.secondary,
      ),
    );

    return ConstrainedBox(
      key: const ValueKey('delivery-line'),
      constraints: const BoxConstraints(minHeight: AppDims.touch),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(child: Semantics(liveRegion: true, child: text)),
          if (actionLabel != null && action != null) ...[
            const SizedBox(width: 4),
            TextButton(
              onPressed: action,
              style: TextButton.styleFrom(
                foregroundColor: actionGreen ? AppColors.green : AppColors.ink,
                textStyle: AppText.link.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                padding: const EdgeInsets.only(left: 8, right: 2),
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The website's full delivery bar as an off-white info card: the
/// promise for the chosen area and mode, how long same-day ordering stays
/// open, and the button the website offers (Express, back to Fresh Market,
/// or set a location). In Express mode it also offers "Shop Express items".
/// Pass [product] on a product page. Home uses the compact [DeliveryLine]
/// instead.
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
      decoration: AppDecor.info,
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
                color: bar.kind == DeliveryBarKind.express
                    ? AppColors.green
                    : AppColors.ink,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text.rich(_spans(bar.message), style: AppText.bodySmall),
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
                      express: action == DeliveryBarAction.express,
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
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.green,
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

/// The delivery bar's button: a white pill with a hairline and ink text;
/// the Express one is green-soft with green text.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.icon,
    required this.express,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool express;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = express ? AppColors.green : AppColors.ink;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: express ? AppColors.greenSoft : AppColors.surface,
        shape: StadiumBorder(
          side: express
              ? BorderSide.none
              : const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      style: AppText.label.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
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

/// The one-line delivery promise of a product card (11.5/500, ellipsized);
/// nothing until a delivery area is set.
///
/// * An Express item while Express can deliver now: green bolt and its
///   time ("35 min" in Fresh Market mode, "30–40 min" in Express mode).
/// * Otherwise a truck (or, in Express mode, a storefront for an item that
///   is not on Express) and the rules' line in grey ("Within 6 hrs",
///   "Fresh Market · Tomorrow by 11 AM", "From 8 AM").
///
/// Screen readers hear the rules' full line ("Within 6 hrs · or 35 min").
class DeliveryPromiseLine extends StatelessWidget {
  const DeliveryPromiseLine({super.key, required this.product});

  final Product product;

  /// Lines the card keeps room for.
  static const int maxLines = 1;
  static const double fontSize = 11.5;
  static const double lineHeight = 1.3;

  /// Space above the line.
  static const double topGap = 4;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore?>();
    final promise = store?.promiseFor(product);
    if (store == null || promise == null) return const SizedBox.shrink();
    final express = store.express!;

    final IconData icon;
    final String text;
    final bool green;
    switch (promise.kind) {
      case ProductPromiseKind.express:
        icon = Icons.bolt;
        text = promise.text;
        green = express.open;
      case ProductPromiseKind.marketOnly:
        icon = Icons.storefront_outlined;
        text = promise.text;
        green = false;
      case ProductPromiseKind.market:
        if (promise.highlight != null) {
          // An Express item while Express is live: its own time.
          icon = Icons.bolt;
          text = '${express.etaMinutes} min';
          green = true;
        } else {
          icon = Icons.local_shipping_outlined;
          text = promise.text;
          green = false;
        }
    }

    return Padding(
      key: const ValueKey('promise-line'),
      padding: const EdgeInsets.only(top: topGap),
      child: Semantics(
        label: promise.text,
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: green ? AppColors.green : AppColors.tertiary,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text.rich(
                TextSpan(text: text),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppText.family,
                  fontFamilyFallback: AppText.fallback,
                  fontSize: fontSize,
                  height: lineHeight,
                  fontWeight: green ? FontWeight.w700 : FontWeight.w500,
                  color: green ? AppColors.green : AppColors.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Product detail's delivery card (off-white, radius 12): when this item
/// reaches the chosen area by Fresh Market and, for an Express item, by
/// Express (in green); in Express mode an item that is not on Express says
/// so and offers Fresh Market.
class ProductDeliveryInfo extends StatelessWidget {
  const ProductDeliveryInfo({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeliveryStore>();
    final area = store.area;
    final now = store.now();

    Widget row(
      IconData icon,
      String text, {
      bool strong = false,
      bool green = false,
    }) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: green ? AppColors.green : AppColors.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: AppText.bodySmall.copyWith(
                    color: green ? AppColors.green : AppColors.ink,
                    fontWeight: strong || green
                        ? FontWeight.w700
                        : FontWeight.w500,
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
      final expressLive = DeliveryCopy.expressLive(area, now);
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
          row(Icons.bolt, expressLine, strong: true, green: expressLive),
          row(Icons.local_shipping_outlined, marketLine),
        ];
      } else {
        rows = [
          row(Icons.local_shipping_outlined, marketLine, strong: true),
          if (eligible)
            row(Icons.bolt, 'Express: $expressLine', green: expressLive),
        ];
      }
    }

    return Container(
      key: const ValueKey('product-delivery'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 4, 2),
      decoration: AppDecor.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
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

/// The delivery card at the top of the cart (off-white info card): mode,
/// place and promise with a "Change" link, and in Express mode a note
/// about items that are not on Express.
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
          ? '${market.line} · by ${by.replaceAll(' ', ' ')}'
          : market.line;
    }
    final mismatch = store.isExpress && split.other > 0
        ? notOnExpress(split.other, market)
        : null;

    return _card(
      icon: store.isExpress ? Icons.bolt : Icons.local_shipping_outlined,
      green: store.isExpress && express.open,
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
    bool green = false,
    String? note,
  }) {
    return Container(
      key: const ValueKey('cart-delivery'),
      decoration: AppDecor.info,
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
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
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: green ? AppColors.green : AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.cardHeading.copyWith(fontSize: 15),
                    ),
                    for (final (i, line) in lines.indexed)
                      Text(
                        line,
                        style: AppText.bodySmall.copyWith(
                          color: i == 0
                              ? AppColors.ink
                              : (green ? AppColors.green : AppColors.secondary),
                          fontWeight: i == 0 || !green
                              ? FontWeight.w400
                              : FontWeight.w600,
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
              margin: const EdgeInsets.fromLTRB(0, 10, 8, 0),
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.all(Radius.circular(10)),
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
                      style: AppText.bodySmall.copyWith(
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
