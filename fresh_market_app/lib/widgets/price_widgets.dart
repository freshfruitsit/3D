import 'package:material_ui/material_ui.dart';

import '../models/money.dart';
import '../theme/app_theme.dart';

/// The discount badge: saving-orange tag with white text, "−46%".
class SalePill extends StatelessWidget {
  const SalePill({super.key, required this.percent});

  final int percent;

  /// The text shown: a real minus sign (U+2212), the percent and "%".
  static String labelFor(int percent) => '\u2212$percent%';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const BoxDecoration(
        color: AppColors.saving,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        labelFor(percent),
        semanticsLabel: '$percent percent off',
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
        style: AppText.tag.copyWith(
          fontSize: 12,
          color: AppColors.onDark,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// An amount with the Dirham sign that screen readers hear as "AED 12.50".
/// Use it for any price outside [PriceRow] (line totals, summaries).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.style = AppText.price,
    this.textAlign,
    this.prefix = '',
  });

  /// Minor units (fils).
  final int cents;
  final TextStyle style;
  final TextAlign? textAlign;

  /// Shown and spoken before the amount, e.g. "Subtotal ".
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$prefix${formatMoney(cents)}',
      semanticsLabel: '$prefix${moneySemantics(cents)}',
      maxLines: 1,
      textAlign: textAlign,
      style: style,
    );
  }
}

/// A price with the struck-through old price beside it.
///
/// Pass [oldPriceCents] only when the item is on sale (`variant.oldPriceCents`
/// and `line.oldLineTotalCents` already follow that rule); the price is then
/// drawn in saving orange. Use `large: true` for the 24/800 price on product
/// detail; add a trailing [SalePill] there through [trailing].
///
/// With [wrap] (the default) the price keeps the shopper's text size: when
/// the parts do not fit one line, the old price (and [trailing]) go to the
/// next line. Without it the row stays one line and shrinks to fit (a
/// fixed-height product card at normal text sizes).
///
/// Screen readers hear "AED 12.50, was AED 23.00".
class PriceRow extends StatelessWidget {
  const PriceRow({
    super.key,
    required this.priceCents,
    this.oldPriceCents,
    this.large = false,
    this.trailing,
    this.wrap = true,
  });

  final int priceCents;
  final int? oldPriceCents;
  final bool large;
  final Widget? trailing;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final old = oldPriceCents;
    final showOld = old != null && old > priceCents;
    final gap = large ? 8.0 : 6.0;
    final price = Text(
      formatMoney(priceCents),
      semanticsLabel: moneySemantics(priceCents),
      maxLines: 1,
      style: (large ? AppText.priceLarge : AppText.price).copyWith(
        color: showOld ? AppColors.saving : null,
      ),
    );
    final oldText = showOld
        ? Text(
            // The currency is already on the price next to it.
            formatAmount(old),
            semanticsLabel: 'was ${moneySemantics(old)}',
            maxLines: 1,
            style: large
                ? AppText.oldPrice.copyWith(fontSize: 15)
                : AppText.oldPrice,
          )
        : null;
    if (wrap) {
      // Bottom-aligned runs: the baselines of the price, the old price and
      // the badge sit within a pixel of each other.
      return Wrap(
        spacing: gap,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          // Only a price wider than the whole line shrinks.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: price,
          ),
          ?oldText,
          ?trailing,
        ],
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          price,
          if (oldText != null) ...[SizedBox(width: gap), oldText],
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}
