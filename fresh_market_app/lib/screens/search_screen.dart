import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../data/catalog.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../theme/app_theme.dart';
import '../widgets/add_control.dart';
import '../widgets/app_search_field.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/price_widgets.dart';
import '../widgets/product_image.dart';
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

  Future<void> _search(String query) async {
    final request = ++_request;
    final api = context.read<ShopifyApi>();
    setState(() {
      _query = query;
      _loading = true;
      _error = null;
    });
    try {
      final results =
          await api.search(query, limit: SearchScreen.resultLimit);
      if (!mounted || request != _request) return;
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
    final bottom = AppDims.bottomBarSpace(context);

    if (_query.isEmpty) {
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(AppDims.gutter, 12, AppDims.gutter, bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Popular searches', style: AppText.cardHeading),
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
      return Align(
        alignment: Alignment.topCenter,
        child: const LoadingView(),
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

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(AppDims.gutter, 4, AppDims.gutter, bottom),
      itemCount: count + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Row(
            children: [
              Expanded(
                child: Text(
                  caption,
                  style: AppText.caption.copyWith(color: AppColors.secondary),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          );
        }
        final product = _results[index - 1];
        return _ResultRow(key: ValueKey(product.id), product: product);
      },
    );
  }
}

class _PopularChip extends StatelessWidget {
  const _PopularChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search for $label',
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: AppText.body.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One result: thumbnail, name, size line, price and the add control.
/// Tapping the row opens the product.
class _ResultRow extends StatelessWidget {
  const _ResultRow({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final variant = product.defaultVariant;
    final sizeLine = product.sizeLine(variant);
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDims.cardBorderRadius,
        side: BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          FocusManager.instance.primaryFocus?.unfocus();
          AppNav.openProduct(context, product);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: ProductImage(url: product.imageUrl, logicalWidth: 64),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.productName,
                    ),
                    if (sizeLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        sizeLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption
                            .copyWith(color: AppColors.secondary),
                      ),
                    ],
                    if (variant != null) ...[
                      const SizedBox(height: 4),
                      PriceRow(
                        priceCents: variant.priceCents,
                        oldPriceCents: variant.oldPriceCents,
                        trailing: variant.salePercent == null
                            ? null
                            : SalePill(percent: variant.salePercent!),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AddControl(product: product, variant: variant),
            ],
          ),
        ),
      ),
    );
  }
}
