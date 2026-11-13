import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/brand_tile.dart';
import '../widgets/category_tile.dart';
import '../widgets/delivery_widgets.dart';
import '../widgets/product_card.dart';
import '../widgets/promo_row.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';

/// The Home tab: the white header (wordmark and location chip, search,
/// delivery mode switch, delivery line), banners, categories, product
/// rails, the brands grid, the offers row and the "Made in UAE" card, with
/// [AppDims.sectionGap] between sections.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// How many products a rail shows before "See all".
  static const int railLimit = 10;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// What one rail currently has to show.
class _RailData {
  const _RailData({this.products, this.error, this.loading = false});

  /// Null until the first successful load.
  final List<Product>? products;

  /// Shopper-safe message of the last failed load.
  final String? error;

  final bool loading;
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, _RailData> _rails = {};

  /// Latest request number per rail, so a slow old answer cannot overwrite
  /// a newer one.
  final Map<String, int> _requests = {};

  @override
  void initState() {
    super.initState();
    for (final rail in Catalog.rails) {
      _rails[rail.handle] = const _RailData(loading: true);
      unawaited(_loadRail(rail));
    }
  }

  Future<void> _loadRail(HomeRail rail) async {
    final handle = rail.handle;
    final request = (_requests[handle] ?? 0) + 1;
    _requests[handle] = request;
    final before = _rails[handle];
    if (before == null || !before.loading) {
      setState(() {
        // Keep showing what is there while it reloads.
        _rails[handle] = _RailData(products: before?.products, loading: true);
      });
    }
    _RailData next;
    try {
      final products = await context.read<ShopifyApi>().collectionProducts(
            handle,
            limit: HomeScreen.railLimit,
          );
      next = _RailData(products: products);
    } on ApiException catch (e) {
      next = _RailData(error: e.userMessage);
    } catch (_) {
      next = const _RailData(error: 'Something went wrong. Please try again.');
    }
    if (!mounted || _requests[handle] != request) return;
    setState(() => _rails[handle] = next);
  }

  Future<void> _refresh() => Future.wait(Catalog.rails.map(_loadRail));

  /// [afterGrid]: the rail follows a tile grid (see [_Section.afterGrid]).
  Widget _rail(HomeRail rail, {bool afterGrid = false}) => _ProductRail(
        rail: rail,
        style: _railStyles[rail.handle] ?? _defaultRailStyle,
        data: _rails[rail.handle] ?? const _RailData(loading: true),
        onRetry: () => _loadRail(rail),
        afterGrid: afterGrid,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      // The white header runs up behind the status bar, so no SafeArea at
      // the top; the bottom is cleared by the list's padding.
      body: RefreshIndicator(
        color: AppColors.ink,
        backgroundColor: AppColors.surface,
        edgeOffset: MediaQuery.paddingOf(context).top,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            // Extra room so the last card can scroll clear of the Ask
            // button, which floats above the bottom bar.
            bottom: AppDims.floatingSpace(context),
          ),
          children: [
            const _Header(),
            const SizedBox(height: 20),
            const _BannerCarousel(),
            const _Section(
              title: 'Shop By Category',
              icon: Icons.grid_view_rounded,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppDims.gutter),
                child: CategoryGrid(),
              ),
            ),
            for (final rail in Catalog.railsBeforeBrands)
              _rail(rail, afterGrid: rail == Catalog.railsBeforeBrands.first),
            const _Section(
              title: 'Brands We Love',
              icon: Icons.favorite,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppDims.gutter),
                child: BrandGrid(),
              ),
            ),
            for (final rail in Catalog.railsAfterBrands)
              _rail(rail, afterGrid: rail == Catalog.railsAfterBrands.first),
            const _Section(
              title: 'Offers',
              icon: Icons.campaign,
              child: PromoRow(),
            ),
            for (final rail in Catalog.railsAfterOffers) _rail(rail),
            const SizedBox(height: AppDims.sectionGap),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppDims.gutter),
              child: _LocalCard(),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Home section: [AppDims.sectionGap] above, the ink heading tag (with
/// "See all" when [onViewAll] is set), [AppDims.headingGap], then [child].
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.onViewAll,
    this.afterGrid = false,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback? onViewAll;

  /// The section follows a category or brand grid. Those keep two label
  /// lines free under every tile and the last row's names take one, so
  /// the gap above is shortened by that free line: what the eye sees stays
  /// [AppDims.sectionGap].
  final bool afterGrid;

  static double gapAbove(BuildContext context, {bool afterGrid = false}) {
    if (!afterGrid) return AppDims.sectionGap;
    final freeLine =
        SquareTile.labelHeight(context) / SquareTile.labelLines + 2;
    return (AppDims.sectionGap - freeLine).clamp(8.0, AppDims.sectionGap);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: gapAbove(context, afterGrid: afterGrid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(title: title, icon: icon, onViewAll: onViewAll),
          const SizedBox(height: AppDims.headingGap),
          child,
        ],
      ),
    );
  }
}

/// Heading tag icon of each Home rail, by collection handle (every tag is
/// ink with a green stripe).
const Map<String, ({IconData icon})> _railStyles = {
  'fresh-meat': (icon: Icons.local_fire_department),
  'best-deals': (icon: Icons.sell),
  'best-sellers': (icon: Icons.eco),
  'berries': (icon: Icons.spa),
  'ambrosia-flowers': (icon: Icons.local_florist),
};

const ({IconData icon}) _defaultRailStyle = (icon: Icons.eco);

/// The white header that runs up behind the status bar, finished with a
/// hairline (no coloured bar):
///
/// 1. the FRESH® MARKET wordmark at the left and the location chip at the
///    right end;
/// 2. the search field (opens Search);
/// 3. the website's Fresh Market / Express switch;
/// 4. the compact delivery line for the chosen area and mode.
class _Header extends StatelessWidget {
  const _Header();

  /// Height of the wordmark.
  static const double logoHeight = 30;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppDims.gutter,
          top + 8,
          AppDims.gutter,
          2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset(
                  Catalog.logoWideAsset,
                  key: const ValueKey('home-logo'),
                  height: logoHeight,
                  fit: BoxFit.contain,
                  semanticLabel: 'Fresh Market',
                ),
                const SizedBox(width: 12),
                const Spacer(),
                const LocationChip(),
              ],
            ),
            const SizedBox(height: 12),
            SearchFieldButton(onTap: () => AppNav.openSearch(context)),
            const SizedBox(height: 12),
            const DeliveryModeSwitch(),
            const SizedBox(height: 6),
            // Two planned lines: the bold time, then the detail.
            const DeliveryLine(stacked: true),
          ],
        ),
      ),
    );
  }
}

/// The three bundled banners with page dots. Advances by itself; a tap
/// opens the banner's collection.
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel();

  /// Width / height of the banner area (the first banner's own shape; the
  /// taller ones are cropped top and bottom).
  static const double aspectRatio = 780 / 332;

  static const Duration interval = Duration(seconds: 5);

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_BannerCarousel.interval, (_) => _advance());
  }

  void _advance() {
    if (!mounted || !_controller.hasClients) return;
    // Do not move the banners while the tab is hidden or covered.
    if (!TickerMode.valuesOf(context).enabled) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final next = (_page + 1) % Catalog.banners.length;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const banners = Catalog.banners;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final height = (constraints.maxWidth - 2 * AppDims.gutter) /
                _BannerCarousel.aspectRatio;
            return SizedBox(
              height: height,
              child: PageView.builder(
                controller: _controller,
                itemCount: banners.length,
                onPageChanged: (index) {
                  setState(() => _page = index);
                  _restartTimer();
                },
                itemBuilder: (context, index) {
                  final banner = banners[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDims.gutter,
                    ),
                    child: Semantics(
                      button: true,
                      label: 'Shop ${banner.title}',
                      child: Material(
                        key: ValueKey('banner-$index'),
                        color: AppColors.subtle,
                        borderRadius: AppDims.bannerBorderRadius,
                        clipBehavior: Clip.antiAlias,
                        child: Ink.image(
                          image: AssetImage(banner.asset),
                          fit: BoxFit.cover,
                          child: InkWell(
                            onTap: () => AppNav.openCollection(
                              context,
                              handle: banner.handle,
                              title: banner.title,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < banners.length; i++)
                AnimatedContainer(
                  key: ValueKey('banner-dot-$i'),
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.ink : _dotGrey,
                    borderRadius: AppDims.pillBorderRadius,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Inactive page dots: the tertiary grey, lightened (decoration only).
  static final Color _dotGrey = AppColors.tertiary.withValues(alpha: 0.4);
}

/// One horizontal product rail: heading with "See all", then cards, a
/// skeleton while loading or a retry row on failure. A collection with no
/// products shows nothing at all (not even the space above it).
class _ProductRail extends StatelessWidget {
  const _ProductRail({
    required this.rail,
    required this.style,
    required this.data,
    required this.onRetry,
    this.afterGrid = false,
  });

  final HomeRail rail;
  final ({IconData icon}) style;
  final _RailData data;
  final VoidCallback onRetry;
  final bool afterGrid;

  @override
  Widget build(BuildContext context) {
    final products = data.products;
    final height = ProductCard.heightOf(context);

    final Widget content;
    if (products != null) {
      if (products.isEmpty) return const SizedBox.shrink();
      content = SizedBox(
        height: height,
        child: ListView.separated(
          key: PageStorageKey('rail-${rail.handle}'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppDims.gutter),
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(width: ProductCard.gap),
          itemBuilder: (context, index) => SizedBox(
            width: ProductCard.railWidth,
            child: ProductCard(product: products[index]),
          ),
        ),
      );
    } else if (data.error != null) {
      content = ErrorView(
        message: data.error!,
        onRetry: onRetry,
        compact: true,
      );
    } else {
      content = _RailSkeleton(
        key: ValueKey('rail-loading-${rail.handle}'),
        height: height,
      );
    }

    return _Section(
      title: rail.title,
      icon: style.icon,
      afterGrid: afterGrid,
      onViewAll: () => AppNav.openCollection(
        context,
        handle: rail.handle,
        title: rail.title,
      ),
      child: content,
    );
  }
}

/// Card-shaped placeholders shown while a rail loads for the first time.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading products',
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: AppDims.gutter),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: ProductCard.gap),
          itemBuilder: (context, index) => const SizedBox(
            width: ProductCard.railWidth,
            child: ProductCardSkeleton(wellHeight: ProductCard.wellHeight),
          ),
        ),
      ),
    );
  }
}

/// The "Made in UAE" card: a white card with the local-produce photo, an
/// ink heading and an ink outlined "Discover now" (not a buying action, so
/// not green).
class _LocalCard extends StatelessWidget {
  const _LocalCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 666 / 279,
            child: ExcludeSemantics(
              child: Image.asset(Catalog.localAsset, fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MADE IN UAE',
                  style: AppText.tag.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: const Text(
                    'Discover our fresh local products',
                    style: AppText.heading,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Organic tomatoes, beetroot, marrow, capsicum and more, '
                  'grown in the UAE and picked for you within 24 hours.',
                  style: AppText.bodySmall.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => AppNav.openCollection(
                    context,
                    handle: Catalog.localHandle,
                    title: Catalog.localTitle,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Discover now'),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
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
