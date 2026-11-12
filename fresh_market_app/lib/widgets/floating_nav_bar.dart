import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The five tabs of the app, in bar order.
enum AppTab {
  home('Home', Icons.home_outlined, Icons.home),
  categories('Categories', Icons.grid_view_outlined, Icons.grid_view_rounded),
  deals('Deals', Icons.local_offer_outlined, Icons.local_offer),
  cart('Cart', Icons.shopping_bag_outlined, Icons.shopping_bag),
  account('Account', Icons.person_outline, Icons.person);

  const AppTab(this.label, this.icon, this.activeIcon);

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// The floating white bottom bar. The shell places it; screens never build
/// it themselves.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.current,
    required this.onSelected,
    this.cartCount = 0,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelected;
  final int cartCount;

  /// Height of the bar itself.
  static const double height = 64;

  /// Inset from the screen sides and from the bottom.
  static const double sideInset = 14;
  static const double bottomInset = 12;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: sideInset),
      decoration: const ShapeDecoration(
        color: AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
        shadows: AppDecor.floatShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              for (final tab in AppTab.values)
                Expanded(
                  child: _NavItem(
                    tab: tab,
                    active: tab == current,
                    badge: tab == AppTab.cart ? cartCount : 0,
                    onTap: () => onSelected(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.badge,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = badge > 0
        ? '${tab.label}, $badge ${badge == 1 ? 'item' : 'items'}'
        : tab.label;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  width: 52,
                  height: 30,
                  decoration: BoxDecoration(
                    color: active ? AppColors.brand : const Color(0x0000732F),
                    borderRadius: const BorderRadius.all(Radius.circular(15)),
                  ),
                  child: Icon(
                    active ? tab.activeIcon : tab.icon,
                    size: 21,
                    color: active ? Colors.white : AppColors.secondary,
                  ),
                ),
                if (badge > 0)
                  Positioned(
                    top: -5,
                    right: 2,
                    child: _Badge(count: badge),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              textScaler: MediaQuery.textScalerOf(context)
                  .clamp(maxScaleFactor: 1.2),
              style: TextStyle(
                fontFamily: AppText.family,
                fontSize: 11,
                height: 1.2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.ink : AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Red count badge (cart). Shows "99+" above 99.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => _Badge(count: count);
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const ShapeDecoration(
        color: AppColors.red,
        shape: StadiumBorder(
          side: BorderSide(color: AppColors.surface, width: 1.5),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        textScaler: TextScaler.noScaling,
        style: const TextStyle(
          fontFamily: AppText.family,
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
