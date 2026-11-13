import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/product_card.dart';
import '../widgets/state_views.dart';

/// Live product search: results appear shortly after typing stops. Opens
/// inside the current tab, so the bottom bar stays.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Text to search for straight away (brand tiles, popular chips).
  final String? initialQuery;

  /// How long typing must pause before the store is asked.
  static const Duration debounce = Duration(milliseconds: 350);

  /// The most results the store's search answers with.
  static const int resultLimit = 10;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  /// Goes up with every search started, so a slow answer to an older
  /// query never replaces a newer one.
  int _request = 0;

  /// The query the body is showing (or loading); empty shows the chips.
  String _query = '';
  bool _loading = false;
  ApiException? _error;
  List<Product> _results = const [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    _controller = TextEditingController(text: initial);
    if (initial.isNotEmpty) {
      _controller.selection =
          TextSelection.collapsed(offset: initial.length);
      _search(initial);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      _request++;
      setState(() {
        _query = '';
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    if (query == _query && _error == null) return;
    _debounce = Timer(SearchScreen.debounce, () => _search(query));
  }

  void _onSubmitted(String text) {
    _debounce?.cancel();
    final query = text.trim();
    if (query.isEmpty || (query == _query && _error == null)) return;
    _search(query);
  }

  void _usePopular(String term) {
    _debounce?.cancel();
    _controller.value = TextEditingValue(
      text: term,
      selection: TextSelection.collapsed(offset: term.length),
    );
    _focus.unfocus();
    _search(term);
  }

  /// A pre-filled search comes from a brand tile, where the store's loose
  /// matching (descriptions) would show unrelated products under the
  /// brand's name. Those keep only products that name the term.
  bool _isInitialQuery(String query) =>
      query.toLowerCase() == widget.initialQuery?.trim().toLowerCase();

  /// True when the product's title, vendor or a tag (`brand:Jazz`,
  /// `origin:Thailand`) contains [term].
  static bool _mentions(Product product, String term) {
    final wanted = term.toLowerCase();
    return product.title.toLowerCase().contains(wanted) ||
        product.vendor.toLowerCase().contains(wanted) ||
        product.tags.any((tag) => tag.toLowerCase().contains(wanted));
  }

  Future<void> _search(String query) async {
    final request = ++_request;
    final api = context.read<ShopifyApi>();
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      var results =
          await api.search(query, limit: SearchScreen.resultLimit);
      if (!mounted || request != _request) return;
      if (_isInitialQuery(query)) {
        results = results.where((p) => _mentions(p, query)).toList();
      }
      setState(() {
        _results = results;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _results = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = (widget.initialQuery?.trim() ?? '').isNotEmpty;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          // Stretch, so short content (the popular chips) keeps the page
          // gutter instead of being centred.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.gutter,
                8,
                AppDims.gutter,
                8,
              ),
              child: Row(
                children: [
                  if (Navigator.of(context).canPop()) ...[
                    CircleIconButton.back(context),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: AppSearchField(
                      controller: _controller,
                      focusNode: _focus,
                      // A pre-filled search shows its results first; the
                      // keyboard would cover them.
                      autofocus: !hasInitial,
                      onChanged: _onChanged,
                      onSubmitted: _onSubmitted,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final bottom = AppDims.floatingSpace(context);

    if (_query.isEmpty) {
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(AppDims.gutter, 16, AppDims.gutter, bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: const Text('Popular searches', style: AppText.cardHeading),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final term in Catalog.popularSearches)
                  _PopularChip(label: term, onTap: () => _usePopular(term)),
              ],
            ),
          ],
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: ErrorView(
          message: error.userMessage,
          onRetry: () => _search(_query),
        ),
      );
    }

    if (_loading && _results.isEmpty) {
      // Card-shaped placeholders where the results will appear.
      return Semantics(
        label: 'Searching',
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppDims.gutter,
            _captionHeight(context),
            AppDims.gutter,
            bottom,
          ),
          gridDelegate: ProductCard.gridDelegate(context),
          itemCount: 4,
          itemBuilder: (context, index) =>
              const ExcludeSemantics(child: ProductCardSkeleton()),
        ),
      );
    }

    if (_results.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: EmptyView(
          icon: Icons.search_off,
          title: 'No results for "$_query"',
          message: 'Check the spelling or try a shorter word.',
          actionLabel: 'Clear search',
          onAction: () {
            _controller.clear();
            _onChanged('');
            _focus.requestFocus();
          },
        ),
      );
    }

    final count = _results.length;
    final caption = count >= SearchScreen.resultLimit
        ? 'Top $count results'
        : count == 1
            ? '1 result'
            : '$count results';

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: _captionHeight(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDims.gutter),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption,
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppDims.gutter),
          sliver: SliverGrid.builder(
            gridDelegate: ProductCard.gridDelegate(context),
            itemCount: count,
            itemBuilder: (context, index) {
              final product = _results[index];
              return ProductCard(
                key: ValueKey(product.id),
                product: product,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  AppNav.openProduct(context, product);
                },
              );
            },
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ],
    );
  }

  /// Height of the "N results" line above the grid (also the space the
  /// loading placeholders leave for it).
  static double _captionHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(AppText.caption.fontSize!) *
          AppText.caption.height! +
      20;
}

/// A popular search: white pill with a hairline, a small grey trend icon
/// and the term.
class _PopularChip extends StatelessWidget {
  const _PopularChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search for $label',
      onTap: onTap,
      excludeSemantics: true,
      child: OutlinedButton.icon(
        style: AppButtons.chip,
        onPressed: onTap,
        icon: const Icon(
          Icons.trending_up,
          size: 16,
          color: AppColors.secondary,
        ),
        label: Text(label),
      ),
    );
  }
}
