import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../theme/app_theme.dart';

/// The "Offers" row: portrait photo banners (radius 14, no border) that
/// scroll sideways. A tap opens the banner's collection. Includes the page
/// gutter.
class PromoRow extends StatelessWidget {
  const PromoRow({super.key, this.onSelected});

  /// Defaults to opening the banner's product list.
  final ValueChanged<PromoEntry>? onSelected;

  static const double bannerWidth = 156;
  static const double bannerHeight = 208;
  static const double gap = 12;

  @override
  Widget build(BuildContext context) {
    const promos = Catalog.promos;
    return SizedBox(
      height: bannerHeight,
      child: ListView.separated(
        key: const PageStorageKey('promos'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppDims.gutter),
        itemCount: promos.length,
        separatorBuilder: (_, _) => const SizedBox(width: gap),
        itemBuilder: (context, index) {
          final promo = promos[index];
          return Semantics(
            button: true,
            label: 'Shop ${promo.title}',
            child: SizedBox(
              width: bannerWidth,
              child: Material(
                key: ValueKey('promo-$index'),
                color: AppColors.subtle,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppDims.cardBorderRadius,
                ),
                clipBehavior: Clip.antiAlias,
                child: Ink.image(
                  image: AssetImage(promo.asset),
                  fit: BoxFit.cover,
                  child: InkWell(
                    onTap: () => onSelected != null
                        ? onSelected!(promo)
                        : AppNav.openCollection(
                            context,
                            handle: promo.handle,
                            title: promo.title,
                            onSaleOnly: promo.onSaleOnly,
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
