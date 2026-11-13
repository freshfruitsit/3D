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
import '../widgets/product_card.dart';
import '../widgets/promo_row.dart';
import '../widgets/section_header.dart';
import '../widgets/state_views.dart';

/// The Home tab: header, search, banners, categories, product rails, the
/// brands grid, the offers row and the "Made in UAE" card.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// How many products a rail shows before "View all".
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

  Widget _rail(HomeRail rail) => _ProductRail(
        rail: rail,
        style: _railStyles[rail.handle] ?? _defaultRailStyle,
        data: _rails[rail.handle] ?? const _RailData(loading: true),
        onRetry: () => _loadRail(rail),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // The white header runs up behind the status bar.
        top: false,
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.olive,
          backgroundColor: AppColors.surface,
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
              const SizedBox(height: 16),
              const _BannerCarousel(),
              const SizedBox(height: 20),
              const SectionHeader(
                title: 'Shop By Category',
                tone: SectionTone.lime,
                icon: Icons.grid_view_rounded,
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppDims.gutter),
                child: CategoryGrid(),
              ),
              for (final rail in Catalog.railsBeforeBrands) _rail(rail),
              const SizedBox(height: 20),
              const SectionHeader(
                title: 'Brands We Love',
                tone: SectionTone.ink,
                icon: Icons.favorite,
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppDims.gutter),
                child: BrandGrid(),
              ),
              for (final rail in Catalog.railsAfterBrands) _rail(rail),
              const SizedBox(height: 20),
              const SectionHeader(
                title: 'Offers',
                tone: SectionTone.ink,
                icon: Icons.campaign,
              ),
              const SizedBox(height: 4),
              const PromoRow(),
              for (final rail in Catalog.railsAfterOffers) _rail(rail),
              const SizedBox(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppDims.gutter),
                child: _LocalCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Heading tag colour and icon of each Home rail, by collection handle.
/// Together with the fixed headings, the tones alternate lime and ink down
/// the page: Shop By Category lime, Today's Top Deals ink, Best Deals
/// lime, Brands We Love ink, Fresh Pick lime, Offers ink, Berries lime,
/// Seasonal Blooms ink.
const Map<String, ({SectionTone tone, IconData icon})> _railStyles = {
  'fresh-meat': (tone: SectionTone.ink, icon: Icons.local_fire_department),
  'best-deals': (tone: SectionTone.lime, icon: Icons.sell),
  'best-sellers': (tone: SectionTone.lime, icon: Icons.eco),
  'berries': (tone: SectionTone.lime, icon: Icons.spa),
  'ambrosia-flowers': (tone: SectionTone.ink, icon: Icons.local_florist),
};

const ({SectionTone tone, IconData icon}) _defaultRailStyle =
    (tone: SectionTone.lime, icon: Icons.eco);

/// The white header that runs up behind the status bar: the logo, the
/// (static) delivery area, the "1Hr Express" button and the search field,
/// finished with a thin lime bar.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: AppColors.surface,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppDims.gutter,
              top + 10,
              AppDims.gutter,
              14,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Image.asset(
                      Catalog.logoWideAsset,
                      height: 48,
                      fit: BoxFit.contain,
                      semanticLabel: 'Fresh Market',
                    ),
                    const SizedBox(width: 10),
                    const Expanded(child: _DeliverTo()),
                    const SizedBox(width: 8),
                    const _ExpressButton(),
                  ],
                ),
                const SizedBox(height: 12),
                SearchFieldButton(
                  onTap: () => AppNav.openSearch(context),
                ),
              ],
            ),
          ),
        ),
        const LimeBar(),
      ],
    );
  }
}

/// "Deliver to / Choose your area". Static in this version.
class _DeliverTo extends StatelessWidget {
  const _DeliverTo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Deliver to', style: AppText.caption),
        const SizedBox(height: 1),
        Row(
          children: [
            const Icon(Icons.location_on, size: 17, color: AppColors.olive),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                'Choose your area',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.cardHeading.copyWith(fontSize: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Lime "1Hr Express" button with ink text and bolt; opens that
/// collection.
class _ExpressButton extends StatelessWidget {
  const _ExpressButton();

  static const String _handle = 'express';
  static const String _title = '1Hr Express';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open $_title',
      excludeSemantics: true,
      child: Material(
        color: AppColors.lime,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              AppNav.openCollection(context, handle: _handle, title: _title),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt, size: 18, color: AppColors.ink),
                  const SizedBox(width: 3),
                  Text(
                    _title,
                    style: AppText.caption.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
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

/// The thin bar in the logo's lime under the white Home header.
class LimeBar extends StatelessWidget {
  const LimeBar({super.key});

  static const double height = 4;

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: ColoredBox(color: AppColors.lime),
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
                        color: AppColors.tile,
                        borderRadius: AppDims.cardBorderRadius,
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
        const SizedBox(height: 10),
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
                    color: i == _page ? AppColors.ink : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One horizontal product rail: heading with "View all", then cards, a
/// skeleton while loading or a retry row on failure. A collection with no
/// products shows nothing at all.
class _ProductRail extends StatelessWidget {
  const _ProductRail({
    required this.rail,
    required this.style,
    required this.data,
    required this.onRetry,
  });

  final HomeRail rail;
  final ({SectionTone tone, IconData icon}) style;
  final _RailData data;
  final VoidCallback onRetry;

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

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SectionHeader(
            title: rail.title,
            tone: style.tone,
            icon: style.icon,
            onViewAll: () => AppNav.openCollection(
              context,
              handle: rail.handle,
              title: rail.title,
            ),
          ),
          const SizedBox(height: 4),
          content,
        ],
      ),
    );
  }
}

/// Card-shaped placeholders shown while a rail loads for the first time.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.disabledFill,
            borderRadius: BorderRadius.circular(4),
          ),
        );

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
          itemBuilder: (context, index) => Container(
            width: ProductCard.railWidth,
            decoration: AppDecor.card,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 116,
                  decoration: BoxDecoration(
                    color: AppColors.disabledFill,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 16),
                bar(120, 12),
                const SizedBox(height: 8),
                bar(72, 10),
                const SizedBox(height: 12),
                bar(64, 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Discover our fresh local products" card.
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MADE IN UAE',
                  style: AppText.caption.copyWith(
                    color: AppColors.olive,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Discover our fresh local products',
                  style: AppText.cardHeading,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Organic tomatoes, beetroot, marrow, capsicum and more, '
                  'grown in the UAE and picked for you within 24 hours.',
                  style: AppText.body,
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => AppNav.openCollection(
                    context,
                    handle: Catalog.localHandle,
                    title: Catalog.localTitle,
                  ),
                  child: const Text('Discover now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
