import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../app_nav.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../state/favourites_store.dart';
import '../theme/app_theme.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/product_card.dart';
import '../widgets/state_views.dart';

/// How the grid is ordered.
enum ProductSort {
  featured('Featured'),
  priceLowToHigh('Price: low to high');

  const ProductSort(this.label);
  final String label;
}

/// A two-column product grid: a collection (category tile, banner, rail
/// "View all", the Deals tab) loaded page by page, or the favourites.
class ProductListScreen extends StatefulWidget {
  /// Products of one collection, loaded page by page.
  const ProductListScreen.collection({
    super.key,
    required String this.handle,
    required this.title,
  });

  /// The shopper's favourites, from the FavouritesStore; their price and
  /// stock are refreshed from the store when the list opens.
  const ProductListScreen.favourites({super.key})
      : handle = null,
        title = 'Favourites';

  /// Collection handle; null for the favourites list.
  final String? handle;
  final String title;

  bool get isFavourites => handle == null;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  /// Page size used to fetch a whole collection for price sorting.
  static const int _bulkLimit = 250;

  /// Safety cap on bulk pages (2,000 products).
  static const int _bulkMaxPages = 8;

  /// Start loading the next page this far before the end of the list.
  static const double _loadAheadExtent = 700;

  final ScrollController _scroll = ScrollController();

  /// Collection products in the store's own (featured) order.
  List<Product> _items = const [];
  final Set<int> _ids = {};
  int _nextPage = 1;
  bool _hasMore = true;

  bool _loadingFirst = false;
  bool _loadingMore = false;
  bool _loadingAll = false;
  ApiException? _firstError;
  ApiException? _moreError;
  ApiException? _sortError;

  ProductSort _sort = ProductSort.featured;

  /// Bumped on every reset so answers to old requests are dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    if (widget.isFavourites) {
      _refreshFavourites();
    } else {
      _loadFirst();
    }
  }

  /// Favourites are saved copies; bring their price and stock up to date.
  Future<void> _refreshFavourites() => context
      .read<FavouritesStore>()
      .refresh(context.read<ShopifyApi>());

  @override
  void didUpdateWidget(ProductListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handle != widget.handle) {
      _sort = ProductSort.featured;
      if (widget.isFavourites) {
        _generation++;
        _refreshFavourites();
      } else {
        _loadFirst();
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ---- Loading -----------------------------------------------------------

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    final api = context.read<ShopifyApi>();
    final handle = widget.handle!;
    setState(() {
      _items = const [];
      _ids.clear();
      _nextPage = 1;
      _hasMore = true;
      _loadingFirst = true;
      _loadingMore = false;
      _loadingAll = false;
      _firstError = null;
      _moreError = null;
      _sortError = null;
    });
    try {
      final page = await api.collectionProducts(handle);
      if (!mounted || generation != _generation) return;
      setState(() {
        _appendPage(page, ShopifyApi.pageSize);
        _loadingFirst = false;
      });
      // The whole collection is needed to order it by price.
      if (_sort == ProductSort.priceLowToHigh && _hasMore) {
        await _loadAll();
      } else {
        _checkFillAfterFrame();
      }
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingFirst = false;
        _firstError = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (widget.isFavourites ||
        !_hasMore ||
        _loadingFirst ||
        _loadingMore ||
        _loadingAll ||
        _firstError != null) {
      return;
    }
    final generation = _generation;
    final api = context.read<ShopifyApi>();
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await api.collectionProducts(widget.handle!, page: _nextPage);
      if (!mounted || generation != _generation) return;
      setState(() {
        _appendPage(page, ShopifyApi.pageSize);
        _loadingMore = false;
      });
      _checkFillAfterFrame();
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingMore = false;
        _moreError = e;
      });
    }
  }

  /// Loads every product of the collection (large pages), so a price sort
  /// orders the whole collection and not only the pages seen so far.
  Future<void> _loadAll() async {
    // A new generation, so a "load more" answer still on its way is dropped
    // and cannot switch paging back on.
    final generation = ++_generation;
    final api = context.read<ShopifyApi>();
    setState(() {
      _loadingAll = true;
      _loadingMore = false;
      _moreError = null;
      _sortError = null;
    });
    try {
      final all = <Product>[];
      final ids = <int>{};
      for (var page = 1; page <= _bulkMaxPages; page++) {
        final batch = await api.collectionProducts(
          widget.handle!,
          page: page,
          limit: _bulkLimit,
        );
        if (!mounted || generation != _generation) return;
        for (final p in batch) {
          if (ids.add(p.id)) all.add(p);
        }
        if (batch.length < _bulkLimit) break;
      }
      setState(() {
        _items = all;
        _ids
          ..clear()
          ..addAll(ids);
        // Past the cap the list is simply left as it is.
        _hasMore = false;
        _loadingAll = false;
      });
      _jumpToTop();
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingAll = false;
        _sort = ProductSort.featured;
        _sortError = e;
      });
    }
  }

  void _appendPage(List<Product> page, int limit) {
    final fresh = [
      for (final p in page)
        if (_ids.add(p.id)) p,
    ];
    _items = [..._items, ...fresh];
    _nextPage++;
    _hasMore = page.length >= limit;
  }

  Future<void> _refresh() async {
    if (widget.isFavourites) return _refreshFavourites();
    await _loadFirst();
  }

  // ---- Scrolling ---------------------------------------------------------

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_moreError != null) return; // wait for the shopper's "Try again"
    if (_scroll.position.extentAfter < _loadAheadExtent) _loadMore();
  }

  /// A short page may not fill the screen, so no scroll would ever ask for
  /// the next one.
  void _checkFillAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
  }

  void _jumpToTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // ---- Sorting -----------------------------------------------------------

  void _toggleSort() {
    final next = _sort == ProductSort.featured
        ? ProductSort.priceLowToHigh
        : ProductSort.featured;
    setState(() {
      _sort = next;
      _sortError = null;
    });
    if (next == ProductSort.priceLowToHigh &&
        !widget.isFavourites &&
        _hasMore &&
        !_loadingFirst &&
        _firstError == null) {
      _loadAll();
    } else {
      _jumpToTop();
    }
  }

  static int _priceOf(Product p) =>
      p.defaultVariant?.priceCents ?? 0x7fffffff;

  List<Product> _sorted(List<Product> source) {
    if (_sort == ProductSort.featured) return source;
    // Stable: equal prices keep the store's order.
    final indexed = [
      for (var i = 0; i < source.length; i++) (i, source[i]),
    ]..sort((a, b) {
        final byPrice = _priceOf(a.$2).compareTo(_priceOf(b.$2));
        return byPrice != 0 ? byPrice : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final favourites = widget.isFavourites
        ? context.watch<FavouritesStore>().products
        : null;
    final source = favourites ?? _items;
    final products = _sorted(source);
    final canPop = Navigator.of(context).canPop();
    final bottomSpace = AppDims.floatingSpace(context);

    final showLoading = !widget.isFavourites && (_loadingFirst || _loadingAll);
    final firstError = widget.isFavourites ? null : _firstError;

    final List<Widget> content;
    if (showLoading) {
      content = [
        SliverFillRemaining(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSpace),
            child: const LoadingView(),
          ),
        ),
      ];
    } else if (firstError != null) {
      content = [
        SliverFillRemaining(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSpace),
            child: ErrorView(
              message: firstError.userMessage,
              onRetry: _loadFirst,
            ),
          ),
        ),
      ];
    } else if (products.isEmpty) {
      content = [
        SliverFillRemaining(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomSpace),
            child: widget.isFavourites
                ? EmptyView(
                    icon: Icons.favorite_border,
                    title: 'No favourites yet',
                    message: 'Tap the heart on a product to keep it here.',
                    actionLabel: 'Start shopping',
                    onAction: () => AppNav.goToTab(context, AppTab.home),
                  )
                : EmptyView(
                    title: 'Nothing here right now',
                    message: 'This section has no products at the moment.',
                    actionLabel: 'Start shopping',
                    onAction: () => AppNav.goToTab(context, AppTab.home),
                  ),
          ),
        ),
      ];
    } else {
      content = [
        if (_sortError != null)
          SliverToBoxAdapter(
            child: ErrorView(
              compact: true,
              message: 'Could not sort by price. '
                  '${_sortError!.userMessage}',
              onRetry: _toggleSort,
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppDims.gutter),
          sliver: SliverGrid.builder(
            gridDelegate: ProductCard.gridDelegate(context),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ProductCard(
                key: ValueKey<int>(product.id),
                product: product,
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: _footer()),
        SliverToBoxAdapter(child: SizedBox(height: bottomSpace)),
      ];
    }

    final showCount = !showLoading && firstError == null && products.isNotEmpty;
    final scrollView = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            title: widget.title,
            showBack: canPop,
            countText: showCount
                ? _countText(products.length, more: !widget.isFavourites && _hasMore)
                : null,
            sort: showCount ? _sort : null,
            onToggleSort: _toggleSort,
          ),
        ),
        ...content,
      ],
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.brand,
          backgroundColor: AppColors.surface,
          onRefresh: _refresh,
          child: scrollView,
        ),
      ),
    );
  }

  static String _countText(int count, {required bool more}) {
    if (more) return '$count+ products';
    return count == 1 ? '1 product' : '$count products';
  }

  Widget _footer() {
    if (_loadingMore) {
      return const LoadingView(padding: EdgeInsets.all(20));
    }
    final error = _moreError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: ErrorView(
          compact: true,
          message: error.userMessage,
          onRetry: _loadMore,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Back arrow (when pushed), 20/800 title, then the "N products" caption
/// with the sort chip.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.showBack,
    required this.countText,
    required this.sort,
    required this.onToggleSort,
  });

  final String title;
  final bool showBack;
  final String? countText;
  final ProductSort? sort;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppDims.gutter, 8, AppDims.gutter, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Row(
              children: [
                if (showBack) ...[
                  CircleIconButton.back(context),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.heading,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (countText != null || sort != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      countText ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ),
                  if (sort != null)
                    _SortChip(sort: sort!, onTap: onToggleSort),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// White pill that switches between the two orders.
class _SortChip extends StatelessWidget {
  const _SortChip({required this.sort, required this.onTap});

  final ProductSort sort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Sort: ${sort.label}. Tap to change',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.touch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_vert, size: 18, color: AppColors.ink),
                  const SizedBox(width: 6),
                  Text(
                    sort.label,
                    style: AppText.caption.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
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
