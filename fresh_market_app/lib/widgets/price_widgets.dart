import 'package:material_ui/material_ui.dart';

import '../models/money.dart';
import '../theme/app_theme.dart';

/// Red sale pill: "-46%".
class SalePill extends StatelessWidget {
  const SalePill({super.key, required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: const BoxDecoration(
        color: AppColors.red,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      child: Text(
        '-$percent%',
        semanticsLabel: '$percent percent off',
        style: const TextStyle(
          fontFamily: AppText.family,
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// A price with the struck-through old price beside it, on one line.
///
/// Pass [oldPriceCents] only when the item is on sale (`variant.oldPriceCents`
/// and `line.oldLineTotalCents` already follow that rule). Use `large: true`
/// for the 24/800 price on product detail; add a trailing [SalePill] there
/// through [trailing].
class PriceRow extends StatelessWidget {
  const PriceRow({
    super.key,
    required this.priceCents,
    this.oldPriceCents,
    this.large = false,
    this.trailing,
  });

  final int priceCents;
  final int? oldPriceCents;
  final bool large;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final old = oldPriceCents;
    final showOld = old != null && old > priceCents;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            formatMoney(priceCents),
            maxLines: 1,
            // A sale price is red, like the sale pill.
            style: (large ? AppText.title : AppText.price)
                .copyWith(color: showOld ? AppColors.red : null),
          ),
          if (showOld) ...[
            SizedBox(width: large ? 8 : 6),
            Text(
              // The currency is already on the price next to it.
              formatMoney(old).replaceFirst('Dhs. ', ''),
              semanticsLabel: 'was ${formatMoney(old)}',
              maxLines: 1,
              style: large
                  ? AppText.oldPrice.copyWith(fontSize: 14)
                  : AppText.oldPrice,
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}
