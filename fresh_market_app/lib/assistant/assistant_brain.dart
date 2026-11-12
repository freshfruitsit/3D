import '../data/catalog.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import 'assistant_intent.dart';

/// Something the shopper can tap under an assistant reply.
sealed class AssistantAction {
  const AssistantAction(this.label);

  /// Button text.
  final String label;
}

/// Shows the Cart tab.
final class OpenCartAction extends AssistantAction {
  const OpenCartAction([super.label = 'Open cart']);
}

/// Opens checkout for the current cart.
final class CheckoutAction extends AssistantAction {
  const CheckoutAction() : super('Go to checkout');
}

/// Opens a collection's product list.
final class OpenCollectionAction extends AssistantAction {
  const OpenCollectionAction(
    super.label, {
    required this.handle,
    required this.title,
  });

  final String handle;
  final String title;
}

/// Opens Search filled with [query].
final class OpenSearchAction extends AssistantAction {
  const OpenSearchAction(this.query) : super('See all results');

  final String query;
}

/// One assistant answer: text, then optional product rows and buttons.
class AssistantReply {
  const AssistantReply(
    this.text, {
    this.products = const [],
    this.actions = const [],
  });

  final String text;

  /// Real store products, at most [AssistantBrain.maxProducts].
  final List<Product> products;
  final List<AssistantAction> actions;
}

/// Answers a message with scripted replies built from live store data.
/// Keyword matching ([AssistantIntentParser]), not AI. Every product and
/// price in a reply comes from [api]; nothing is made up.
class AssistantBrain {
  const AssistantBrain({
    required this.api,
    required this.cart,
    this.retryDelay = const Duration(seconds: 1),
  });

  final ShopifyApi api;
  final CartStore cart;

  /// Wait before the one retry after the store answers 429 (too many
  /// requests).
  final Duration retryDelay;

  /// The most product rows under one reply.
  static const int maxProducts = 3;

  static const String greeting =
      'Hi, I am your Fresh Market assistant. Ask me to find a product, '
      "open a category, add something to your cart or show today's offers.";

  static const String networkError =
      'I could not reach the store. Check your connection and try again.';

  /// Ready-made questions shown above the input.
  static const List<String> suggestions = [
    'Show me berries',
    'What is on offer?',
    'Add 2 cucumbers',
    'Find avocado',
    'Open my cart',
  ];

  static const String _tryHint =
      'Try "Show me berries", "Find avocado" or "Add 2 cucumbers".';

  static const HomeRail _deals = Catalog.bestDeals;

  /// Never throws: a store failure becomes a reply that says so.
  Future<AssistantReply> reply(String message) async {
    final intent = AssistantIntentParser.parse(message);
    try {
      try {
        return await _answer(intent);
      } on HttpStatusException catch (e) {
        if (e.statusCode != 429) rethrow;
        // Nothing has been added yet: every reply reads before it writes.
        await Future<void>.delayed(retryDelay);
        return await _answer(intent);
      }
    } on NetworkException {
      return const AssistantReply(networkError);
    } on ApiException catch (e) {
      return AssistantReply(e.userMessage);
    }
  }

  Future<AssistantReply> _answer(AssistantIntent intent) => switch (intent) {
        AddIntent() => _add(intent),
        RemoveIntent() => Future.value(_remove()),
        CheckoutIntent() => Future.value(_checkout()),
        CartIntent() => Future.value(_cart()),
        OffersIntent() => _offers(),
        CategoryIntent(:final category) => _category(category),
        SearchIntent(:final query) => _search(query),
      };

  /// Searches as typed, then with plurals made singular ("cucumbers" finds
  /// "Cucumber").
  Future<List<Product>> _find(String query, {required int limit}) async {
    final found = await api.search(query, limit: limit);
    if (found.isNotEmpty) return found;
    final singular = AssistantIntentParser.singular(query);
    if (singular == query) return found;
    return api.search(singular, limit: limit);
  }

  Future<AssistantReply> _add(AssistantIntent intent) async {
    intent as AddIntent;
    final query = intent.query;
    if (query.isEmpty) {
      return const AssistantReply(
        'Tell me what to add, for example "Add 2 cucumbers".',
      );
    }
    // The first product in stock is the one added, so a short list is
    // enough; the wider search is only for when all of it is sold out.
    var results = await _find(query, limit: 4);
    if (results.isEmpty) {
      return AssistantReply(
        'I could not find "$query" in the store, so nothing was added. '
        'Try another name, for example "Add 2 cucumbers".',
      );
    }
    if (intent.measureAsked) {
      return AssistantReply(
        'I can only add whole packs, so nothing was added. Choose the '
        'size you want below.',
        products: results.take(maxProducts).toList(),
        actions: [OpenSearchAction(query)],
      );
    }
    if (results.length == 4 && !results.any((p) => p.available)) {
      results = await _find(query, limit: 10);
    }
    final product = results.where((p) => p.available).firstOrNull;
    if (product == null) {
      return AssistantReply(
        '${results.first.title} is sold out right now, so nothing was added.',
        products: [results.first],
      );
    }
    final quantity = intent.quantity;
    final variant = product.defaultVariant!;
    final before = cart.quantityOf(variant.id);
    cart.add(product, variant, quantity: quantity);
    final added = cart.quantityOf(variant.id) - before;
    final name = variant.label == null
        ? product.title
        : '${product.title} (${variant.label})';
    final onlyFirst = intent.moreItems
        ? ' I add one product per message, so ask again for the rest.'
        : '';
    return AssistantReply(
      (added > 0
              ? 'Done. I added $added × $name to your cart.'
              : 'Your cart already holds the most it can of $name '
                  '(${CartStore.maxQuantity}).') +
          onlyFirst,
      products: [product],
      actions: const [OpenCartAction()],
    );
  }

  AssistantReply _remove() => const AssistantReply(
        'I cannot remove items yet. Open your cart to change it.',
        actions: [OpenCartAction()],
      );

  AssistantReply _checkout() {
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is empty, so there is nothing to check out yet. '
        'Ask me to add something first, for example "Add 2 cucumbers".',
      );
    }
    return AssistantReply(
      '${_cartSummary()} Ready when you are.',
      actions: const [CheckoutAction(), OpenCartAction('Review cart')],
    );
  }

  AssistantReply _cart() {
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is empty.',
        actions: [OpenCartAction()],
      );
    }
    return AssistantReply(_cartSummary(), actions: const [OpenCartAction()]);
  }

  String _cartSummary() {
    final count = cart.itemCount;
    return 'Your cart has $count ${count == 1 ? 'item' : 'items'}, '
        'subtotal ${formatMoney(cart.subtotalCents)}.';
  }

  Future<AssistantReply> _offers() async {
    // One collection failing still leaves the other to answer with.
    ApiException? failure;
    Future<List<Product>> load(String handle) async {
      try {
        return await api.collectionProducts(handle);
      } on ApiException catch (e) {
        failure ??= e;
        return const [];
      }
    }

    const rails = [Catalog.topDeals, _deals];
    final loaded = await Future.wait([
      for (final rail in rails) load(rail.handle),
    ]);
    final bestDeals = loaded[1];
    if (loaded.every((list) => list.isEmpty) && failure != null) {
      throw failure!;
    }

    const action = OpenCollectionAction(
      'See all deals',
      handle: Catalog.dealsHandle,
      title: 'Best Deals',
    );

    // Really on sale: the variant the row shows has a higher old price.
    final seen = <int>{};
    final onSale = [
      for (final (index, rail) in rails.indexed)
        for (final product in loaded[index])
          if (product.available &&
              (product.defaultVariant?.onSale ?? false) &&
              seen.add(product.id))
            (rail, product),
    ];
    if (onSale.isNotEmpty) {
      int percent((HomeRail, Product) e) =>
          e.$2.defaultVariant!.salePercent ?? 0;
      // Biggest saving first; equal savings keep the store's order.
      final ranked = [
        for (final (index, entry) in onSale.indexed) (index, entry)
      ]..sort((a, b) {
          final byPercent = percent(b.$2).compareTo(percent(a.$2));
          return byPercent != 0 ? byPercent : a.$1.compareTo(b.$1);
        });
      final shown = [for (final entry in ranked.take(maxProducts)) entry.$2];
      final best = shown.first;
      final saving = percent(best) > 0
          ? ' The biggest saving is ${percent(best)}% on ${best.$2.title}.'
          : '';
      // A button for each collection the rows came from, best first, so
      // the list it opens holds the products shown.
      final shownRails = <HomeRail>[];
      for (final (rail, _) in shown) {
        if (!shownRails.contains(rail)) shownRails.add(rail);
      }
      return AssistantReply(
        'These are on sale today.$saving',
        products: [for (final entry in shown) entry.$2],
        actions: [
          for (final rail in shownRails)
            OpenCollectionAction(
              'See all ${rail.title}',
              handle: rail.handle,
              title: rail.title,
            ),
        ],
      );
    }

    final shown = bestDeals.take(maxProducts).toList();
    if (shown.isEmpty) {
      return const AssistantReply(
        'I could not find any offers in the store right now.',
        actions: [action],
      );
    }
    return AssistantReply(
      'Nothing is marked down right now. Here are products from '
      '${_deals.title}.',
      products: shown,
      actions: const [action],
    );
  }

  Future<AssistantReply> _category(CategoryEntry category) async {
    final title = category.label;
    final List<Product> products;
    try {
      products = await api.collectionProducts(
        category.handle,
        limit: maxProducts,
      );
    } on HttpStatusException catch (e) {
      if (!e.isNotFound) rethrow;
      return AssistantReply('I could not find $title in the store right now.');
    }
    final action = OpenCollectionAction(
      'Open $title',
      handle: category.handle,
      title: title,
    );
    if (products.isEmpty) {
      return AssistantReply(
        '$title has no products in the store right now.',
        actions: [action],
      );
    }
    return AssistantReply(
      'Here is $title.',
      products: products.take(maxProducts).toList(),
      actions: [action],
    );
  }

  Future<AssistantReply> _search(String query) async {
    if (query.isEmpty) {
      return const AssistantReply(
        'Tell me a product or a category and I will look in the store. '
        '$_tryHint',
      );
    }
    // Only [maxProducts] rows are shown; "See all results" has the rest.
    final results = await _find(query, limit: maxProducts);
    if (results.isEmpty) {
      return AssistantReply(
        'I could not find anything for "$query". $_tryHint '
        'You can also ask "What is on offer?".',
      );
    }
    final count = results.length;
    return AssistantReply(
      count == 1
          ? 'I found this for "$query".'
          : 'Here is what I found for "$query".',
      products: results.take(maxProducts).toList(),
      actions: [OpenSearchAction(query)],
    );
  }
}
