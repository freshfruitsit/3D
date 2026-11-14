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

/// The floating bottom bar: an ink pill with a soft shadow. Inactive tabs
/// are grey; the active tab is white with a small green dot under its
/// icon. The shell places it; screens never build it themselves.
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

  /// The bar's fill.
  static const Color background = AppColors.ink;

  /// Size of the green dot under the active icon.
  static const double dotSize = 4;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: sideInset),
      decoration: const ShapeDecoration(
        color: background,
        shape: StadiumBorder(),
        shadows: AppShadows.float,
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
    final color = active ? AppColors.onDark : AppColors.navInactive;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        highlightColor: Colors.transparent,
        splashColor: const Color(0x1FFFFFFF),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  active ? tab.activeIcon : tab.icon,
                  size: 23,
                  color: color,
                ),
                if (badge > 0)
                  Positioned(
                    top: -6,
                    left: 14,
                    child: CountBadge(
                      count: badge,
                      borderColor: FloatingNavBar.background,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            // The active-tab indicator: a small green dot under the icon.
            AnimatedContainer(
              key: active ? const ValueKey('nav-active-dot') : null,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: FloatingNavBar.dotSize,
              height: FloatingNavBar.dotSize,
              decoration: BoxDecoration(
                color: active ? AppColors.green : const Color(0x000E7C3A),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 3),
            // Shrinks to the tab width when the system font is enlarged,
            // so "Categories" is never cut off.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tab.label,
                maxLines: 1,
                softWrap: false,
                textScaler: MediaQuery.textScalerOf(context)
                    .clamp(maxScaleFactor: 1.2),
                style: AppText.navLabel.copyWith(
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green count badge with white text (cart). Shows "99+" above 99.
/// [borderColor] is the ring that separates it from what it sits on: the
/// bar's ink in the bottom bar, white on light surfaces.
class CountBadge extends StatelessWidget {
  const CountBadge({
    super.key,
    required this.count,
    this.borderColor = AppColors.surface,
  });

  final int count;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: ShapeDecoration(
        color: AppColors.green,
        shape: StadiumBorder(side: BorderSide(color: borderColor, width: 1.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        textScaler: TextScaler.noScaling,
        style: AppText.tag.copyWith(
          fontSize: 10,
          height: 1.1,
          fontWeight: FontWeight.w800,
          color: AppColors.onDark,
        ),
      ),
    );
  }
}
