import '../data/catalog.dart';
import '../models/money.dart';
import '../models/product.dart';
import '../services/shopify_api.dart';
import '../state/cart_store.dart';
import '../state/favourites_store.dart';
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
  const OpenSearchAction(this.query, [super.label = 'See all results']);

  final String query;
}

/// Shows the Categories tab.
final class OpenCategoriesAction extends AssistantAction {
  const OpenCategoriesAction([super.label = 'All categories']);
}

/// Opens the favourites list.
final class OpenFavouritesAction extends AssistantAction {
  const OpenFavouritesAction([super.label = 'Open favourites']);
}

/// Sends [message] to the assistant as if the shopper had typed it.
final class SendMessageAction extends AssistantAction {
  const SendMessageAction(super.label, {required this.message});

  final String message;
}

/// Adds one unit of the first available variant of each of [products] to
/// the cart. The screen does the adding and then calls
/// [AssistantSession.note] with what happened.
final class AddProductsAction extends AssistantAction {
  const AddProductsAction(super.label, {required this.products});

  final List<Product> products;
}

/// Empties the cart, after the shopper confirmed. [expected] is what the
/// cart held when the shopper was asked (variant id -> quantity): the
/// screen clears the cart only while it still [matches], then calls
/// [AssistantSession.note].
final class ClearCartAction extends AssistantAction {
  const ClearCartAction(this.expected, [super.label = 'Yes, empty my cart']);

  final Map<int, int> expected;

  /// True while [cart] holds exactly what it held when the shopper was
  /// asked, so the confirmation still covers every item in it.
  bool matches(CartStore cart) =>
      cart.lines.length == expected.length &&
      cart.lines.every((line) => expected[line.variantId] == line.quantity);
}

/// Opens [uri] outside the app: `tel:`, `mailto:` or a store web page.
final class OpenLinkAction extends AssistantAction {
  const OpenLinkAction(super.label, {required this.uri});

  final String uri;
}

/// Which icon a [QuickOption] card shows. The screen maps it to an icon.
enum QuickOptionKind {
  offers,
  categories,
  recipes,
  local,
  gifts,
  popular,
  cart,
  contact,
}

/// A card in the options grid under the greeting: tapping it sends
/// [message].
class QuickOption {
  const QuickOption(this.label, this.message, this.kind);

  final String label;
  final String message;
  final QuickOptionKind kind;
}

/// One assistant answer: text, then optional product rows and buttons.
class AssistantReply {
  const AssistantReply(
    this.text, {
    this.products = const [],
    this.actions = const [],
    this.suggestions = const [],
    this.showOptions = false,
    this.chipProducts = const {},
  });

  final String text;

  /// Real store products, at most [AssistantBrain.maxProducts] (recipe
  /// ideas may show up to [AssistantBrain.maxRecipeProducts]).
  final List<Product> products;
  final List<AssistantAction> actions;

  /// Follow-up questions for the chip row above the input while this is
  /// the latest reply. Empty: the row shows
  /// [AssistantBrain.defaultSuggestions].
  final List<String> suggestions;

  /// Show the [AssistantBrain.quickOptions] grid under this reply.
  final bool showOptions;

  /// The product each product chip of [suggestions] is about ("Add 1
  /// Kiwi", "How much is Kiwi?"), so tapping it acts on that row's product
  /// instead of searching again (a search can find another size or box).
  final Map<String, Product> chipProducts;
}

/// Answers a message with scripted replies built from live store data.
/// Keyword matching ([AssistantIntentParser]), not AI. Every product and
/// price in a reply comes from [api]; nothing is made up.
class AssistantBrain {
  const AssistantBrain({
    required this.api,
    required this.cart,
    this.favourites,
    this.retryDelay = const Duration(seconds: 1),
  });

  final ShopifyApi api;
  final CartStore cart;

  /// For "show my favourites"; null answers like an empty list.
  final FavouritesStore? favourites;

  /// Wait before the one retry after the store answers 429 (too many
  /// requests).
  final Duration retryDelay;

  /// The most product rows under one reply.
  static const int maxProducts = 3;

  /// The most product rows under a recipe idea.
  static const int maxRecipeProducts = 4;

  /// The most store searches one recipe idea runs at the same time, so
  /// the store does not answer 429 (too many requests).
  static const int recipeSearchWidth = 2;

  /// The options grid under the greeting, in order.
  static const List<QuickOption> quickOptions = [
    QuickOption("Today's offers", 'What is on offer?', QuickOptionKind.offers),
    QuickOption(
      'Categories',
      'Show all categories',
      QuickOptionKind.categories,
    ),
    QuickOption('Recipe ideas', 'Recipe ideas', QuickOptionKind.recipes),
    QuickOption('Local UAE', 'Show local UAE produce', QuickOptionKind.local),
    QuickOption('Gifts & flowers', 'Gift ideas', QuickOptionKind.gifts),
    QuickOption('Best sellers', 'What is popular?', QuickOptionKind.popular),
    QuickOption('My cart', 'Open my cart', QuickOptionKind.cart),
    QuickOption(
      'Customer care',
      'Contact customer service',
      QuickOptionKind.contact,
    ),
  ];

  /// The reply that shows the options grid again.
  static const AssistantReply optionsReply = AssistantReply(
    'Here is what I can help with. Tap an option or type your question.',
    showOptions: true,
  );

  /// The chip row when the latest reply has no suggestions of its own.
  static const List<String> defaultSuggestions = [
    'What is on offer?',
    'Show me berries',
    'Add 2 cucumbers',
    'Ideas for a fruit salad',
    'Cheapest avocado',
    'Show local UAE produce',
    'Gift ideas',
    "What's new?",
    'Contact customer service',
    'Open my cart',
  ];

  static const String greeting =
      'Hi, I am your Fresh Market assistant. Ask me to find a product, '
      "open a category, add something to your cart or show today's offers.";

  static const String networkError =
      'I could not reach the store. Check your connection and try again.';

  /// Any other failure while answering.
  static const String unexpectedError =
      'Sorry, something went wrong. Please try again.';

  /// Customer service, exactly as the store's website footer gives it.
  static const String contactText =
      'You can reach Fresh Market customer service on 800 1 627538 '
      '(toll-free) or care@freshmarket.ae, 7 days a week, 8am to 11pm. '
      'The store is in Ras Al Khor, Dubai.';

  /// The payment methods the store's website lists.
  static const String paymentText =
      'The website lists Visa, Mastercard, Apple Pay and cash on delivery. '
      'You choose how to pay at checkout.';

  /// No fees, times or minimums: checkout shows those.
  static const String deliveryText =
      'Fresh Market delivers within the UAE. Many products are in the 1Hr '
      'Express range. You choose the address and delivery time at '
      'checkout, where any fees are shown.';

  static const List<AssistantAction> contactActions = [
    OpenLinkAction('Call 800 1 627538', uri: 'tel:8001627538'),
    OpenLinkAction('Email us', uri: 'mailto:care@freshmarket.ae'),
    OpenLinkAction(
      'Contact page',
      uri: 'https://testtfm.myshopify.com/pages/contact',
    ),
  ];

  static const String _tryHint =
      'Try "Show me berries", "Find avocado" or "Add 2 cucumbers".';

  static const HomeRail _deals = Catalog.bestDeals;

  /// Offered next to Hampers for "gift ideas".
  static const List<AssistantAction> _giftActions = [
    OpenCollectionAction(
      'Open Flowers',
      handle: 'ambrosia-flowers',
      title: 'Flowers',
    ),
    OpenCollectionAction(
      'Open Fruit Bouquets',
      handle: 'ambrosia-bouquets',
      title: 'Fruit Bouquets',
    ),
    OpenCollectionAction(
      'Open Special Occasions',
      handle: 'ambrosia-occasions',
      title: 'Special Occasions',
    ),
  ];

  // Follow-up chips that never depend on the store.
  static const String _offersChip = 'What is on offer?';
  static const String _popularChip = 'What is popular?';
  static const String _categoriesChip = 'Show all categories';
  static const String _cartChip = 'Open my cart';
  static const String _checkoutChip = 'Checkout';
  static const String _emptyCartChip = 'Empty my cart';
  static const String _berriesChip = 'Show me berries';
  static const String _deliveryChip = 'Delivery information';
  static const String _paymentChip = 'Payment methods';
  static const String _contactChip = 'Contact customer service';
  static const String _expressChip = 'Show 1Hr Express';
  static final String _fruitSaladChip =
      AssistantIntentParser.recipes.first.message;

  static const List<String> _startChips = [
    _offersChip,
    _berriesChip,
    'Ideas for a fruit salad',
  ];

  /// Never throws: a store failure becomes a reply that says so.
  ///
  /// [previous] is the reply [message] answers: a yes or no to its "Are
  /// you sure?", or one of its product chips, which acts on the product
  /// it was made from.
  Future<AssistantReply> reply(
    String message, {
    AssistantReply? previous,
  }) async {
    final pending = previous?.actions.whereType<ClearCartAction>().firstOrNull;
    if (pending != null) {
      final yes = AssistantIntentParser.confirmation(message);
      if (yes != null) return _answerClear(pending, yes: yes);
    }
    final target = previous?.chipProducts[message.trim()];
    final intent = AssistantIntentParser.parse(message);
    try {
      try {
        return await _answer(intent, target);
      } on HttpStatusException catch (e) {
        if (e.statusCode != 429) rethrow;
        // Nothing has been changed yet: every reply reads before it
        // writes.
        await Future<void>.delayed(retryDelay);
        return await _answer(intent, target);
      }
    } on NetworkException {
      return const AssistantReply(networkError);
    } on ApiException catch (e) {
      return AssistantReply(e.userMessage);
    }
  }

  /// [target]: the product of the chip that was tapped, if any.
  Future<AssistantReply> _answer(
    AssistantIntent intent,
    Product? target,
  ) async => switch (intent) {
        final AddIntent add => await _add(add, target: target),
        final RemoveIntent remove => _remove(remove),
        ClearCartIntent() => _clearCart(),
        CheckoutIntent() => _checkout(),
        CartIntent() => _cart(),
        OffersIntent() => await _offers(),
        CategoryIntent(:final category) => await _collection(
          category.handle,
          category.label,
          category: category,
        ),
        CollectionIntent(:final collection) => await _collection(
          collection.handle,
          collection.title,
        ),
        AllCategoriesIntent() => _allCategories(),
        final CheapestIntent cheapest => await _cheapest(cheapest),
        PriceIntent(:final query) => await _price(query, target: target),
        StockIntent(:final query) => await _stock(query),
        RecipeIntent(:final recipe) => await _recipe(recipe),
        RecipeIdeasIntent() => _recipeIdeas(),
        FavouritesIntent() => await _favourites(),
        ContactIntent() => const AssistantReply(
          contactText,
          actions: contactActions,
          suggestions: [_deliveryChip, _paymentChip, _offersChip],
        ),
        PaymentIntent() => _payment(),
        DeliveryIntent() => const AssistantReply(
          deliveryText,
          actions: [
            OpenCollectionAction(
              'Open 1Hr Express',
              handle: 'express',
              title: '1Hr Express',
            ),
            SendMessageAction(_contactChip, message: _contactChip),
          ],
          suggestions: [_paymentChip, _expressChip, _cartChip],
        ),
        BrandsIntent() => _brands(),
        HelpIntent(:final greeting) =>
          greeting
              ? const AssistantReply(
                  'Hello! Here is what I can help with. Tap an option or type '
                  'your question.',
                  showOptions: true,
                )
              : optionsReply,
        ThanksIntent(:final farewell) => AssistantReply(
          farewell
              ? 'Thank you for shopping with Fresh Market. Come back any '
                    'time.'
              : 'You are welcome. Is there anything else I can help with?',
          suggestions: const [_offersChip, _cartChip, _categoriesChip],
        ),
        SearchIntent(:final query) => await _search(query),
      };

  // ---- helpers -----------------------------------------------------------

  /// Searches as typed, then with plurals made singular ("cucumbers" finds
  /// "Cucumber").
  Future<List<Product>> _find(String query, {required int limit}) async {
    final found = await api.search(query, limit: limit);
    if (found.isNotEmpty) return found;
    final singular = AssistantIntentParser.singular(query);
    if (singular == query) return found;
    return api.search(singular, limit: limit);
  }

  /// At most three plain words of a product title ("Zespri Kiwi
  /// Sungold"), safe to put into a suggestion: no sizes, numbers or words
  /// that would change what the suggestion asks. Null when none is left.
  static String? shortName(String title) {
    final kept = <String>[];
    for (final match in RegExp(
      r"[\p{L}\p{N}'’]+",
      unicode: true,
    ).allMatches(title)) {
      final piece = match.group(0)!;
      final word = AssistantIntentParser.words(piece).join();
      if (AssistantIntentParser.isPlainWord(word)) kept.add(piece);
      if (kept.length == 3) break;
    }
    return kept.isEmpty ? null : kept.join(' ');
  }

  /// [query] with only plain words, for `Cheapest <query>`; null when none
  /// is left.
  static String? _plainQuery(String query) {
    final kept = AssistantIntentParser.words(query)
        .where(AssistantIntentParser.isPlainWord);
    return kept.isEmpty ? null : kept.join(' ');
  }

  /// [items] without nulls and repeats, at most five.
  static List<String> _chips(Iterable<String?> items) {
    final chips = <String>[];
    for (final item in items) {
      if (item == null || item.isEmpty || chips.contains(item)) continue;
      chips.add(item);
      if (chips.length == 5) break;
    }
    return chips;
  }

  static String? _addChip(Product? product, {bool more = false}) {
    final name = product == null ? null : shortName(product.title);
    return name == null ? null : 'Add 1 ${more ? 'more ' : ''}$name';
  }

  static String? _priceChip(Product? product) {
    final name = product == null ? null : shortName(product.title);
    return name == null ? null : 'How much is $name?';
  }

  /// The chips of [chips] made from [product] by [_addChip] and
  /// [_priceChip], each with [product], for [AssistantReply.chipProducts].
  static Map<String, Product> _chipsFor(List<String> chips, Product? product) =>
      product == null
      ? const {}
      : {
          for (final chip in [
            _addChip(product),
            _addChip(product, more: true),
            _priceChip(product),
          ])
            if (chip != null && chips.contains(chip)) chip: product,
        };

  static String? _cheapestChip(String query) {
    final plain = _plainQuery(query);
    return plain == null ? null : 'Cheapest $plain';
  }

  static String? _stockChip(String query) {
    final plain = _plainQuery(query);
    return plain == null ? null : 'Is $plain in stock?';
  }

  static String? _removeChip(CartLine? line) {
    final name = line == null ? null : shortName(line.title);
    return name == null ? null : 'Remove $name';
  }

  static Product? _firstAvailable(Iterable<Product> products) =>
      products.where((p) => p.available).firstOrNull;

  /// The cheapest of [products] in stock, by the price its row shows;
  /// equal prices keep the store's order. Null when none is in stock.
  static Product? _cheapestAvailable(Iterable<Product> products) {
    Product? best;
    for (final product in products) {
      if (!product.available) continue;
      if (best == null ||
          product.defaultVariant!.priceCents <
              best.defaultVariant!.priceCents) {
        best = product;
      }
    }
    return best;
  }

  /// True when every word of [query] is a word of [title], singular or
  /// plural ("Avocado Hass" names "avocados", "Pineapple" does not name
  /// "apple").
  static bool _titleNames(String title, String query) =>
      AssistantIntentParser.words(query).every((w) => _titleHas(title, w));

  /// The product to add for [query]: the cheapest in stock whose title
  /// names it, so "add an avocado" is not a 10 kg box the store lists
  /// first; then the cheapest that names it in its type, brand or tags;
  /// then the store's first in stock.
  static Product? _pickToAdd(List<Product> results, String query) =>
      _cheapestAvailable(results.where((p) => _titleNames(p.title, query))) ??
      _cheapestAvailable(_naming(results, query)) ??
      _firstAvailable(results);

  /// "Cucumber (500 GM)", or the title alone without options.
  static String _name(Product product, Variant variant) => variant.label == null
      ? product.title
      : '${product.title} (${variant.label})';

  static String _lineName(CartLine line) => line.variantTitle == null
      ? line.title
      : '${line.title} (${line.variantTitle})';

  /// "A", "A and B", "A, B and C".
  static String _join(List<String> items) => switch (items.length) {
    0 => '',
    1 => items.first,
    _ =>
      '${items.sublist(0, items.length - 1).join(', ')} and '
          '${items.last}',
  };

  String _cartSummary() {
    final count = cart.itemCount;
    return 'Your cart has $count ${count == 1 ? 'item' : 'items'}, '
        'subtotal ${formatMoney(cart.subtotalCents)}.';
  }

  AssistantReply _notFound(String query) => AssistantReply(
    'I could not find anything for "$query". $_tryHint '
    'You can also ask "What is on offer?".',
    suggestions: [_categoriesChip, _offersChip, _fruitSaladChip],
  );

  // ---- cart --------------------------------------------------------------

  Future<AssistantReply> _add(AddIntent intent, {Product? target}) async {
    final query = intent.query;
    if (query.isEmpty) {
      return const AssistantReply(
        'Tell me what to add, for example "Add 2 cucumbers".',
        suggestions: _startChips,
      );
    }
    final List<Product> results;
    final Product? product;
    if (target != null && !intent.measureAsked) {
      // A chip under a product row adds that very product, as the store
      // has it now.
      final fresh = await _fresh(target);
      results = [fresh];
      product = fresh.available ? fresh : null;
    } else {
      results = await _find(query, limit: 10);
      if (results.isEmpty) {
        return AssistantReply(
          'I could not find "$query" in the store, so nothing was added. '
          'Try another name, for example "Add 2 cucumbers".',
          suggestions: [_categoriesChip, _offersChip, _fruitSaladChip],
        );
      }
      if (intent.measureAsked) {
        final shown = results.take(maxProducts).toList();
        final pick = _firstAvailable(shown);
        final suggestions = _chips([
          _addChip(pick),
          _cheapestChip(query),
          _cartChip,
        ]);
        return AssistantReply(
          'I can only add whole packs, so nothing was added. Choose the '
          'size you want below.',
          products: shown,
          actions: [OpenSearchAction(query)],
          suggestions: suggestions,
          chipProducts: _chipsFor(suggestions, pick),
        );
      }
      product = _pickToAdd(results, query);
    }
    if (product == null) {
      return AssistantReply(
        '${results.first.title} is sold out right now, so nothing was added.',
        products: [results.first],
        suggestions: _chips([_offersChip, _categoriesChip, _fruitSaladChip]),
      );
    }
    final quantity = intent.quantity;
    final variant = product.defaultVariant!;
    final before = cart.quantityOf(variant.id);
    cart.add(product, variant, quantity: quantity);
    final added = cart.quantityOf(variant.id) - before;
    final name = _name(product, variant);
    final onlyFirst = intent.moreItems
        ? ' I add one product per message, so ask again for the rest.'
        : '';
    // The price is said, so a box or a large pack is plain to see.
    final price = '${variant.priceText}${added > 1 ? ' each' : ''}';
    final suggestions = _chips([
      if (added > 0) _addChip(product, more: true),
      _cartChip,
      _checkoutChip,
      _fruitSaladChip,
    ]);
    return AssistantReply(
      (added > 0
              ? 'Done. I added $added × $name to your cart at $price.'
              : 'Your cart already holds the most it can of $name '
                    '(${CartStore.maxQuantity}).') +
          onlyFirst,
      products: [product],
      actions: const [OpenCartAction()],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, product),
    );
  }

  /// Cart lines whose title (and size) holds every word of [query]; a
  /// plural matches its singular, and "berries" matches "Blueberry".
  List<CartLine> _matchingLines(String query) {
    final wanted = AssistantIntentParser.words(query)
        .map(AssistantIntentParser.singular);
    return [
      for (final line in cart.lines)
        if (_lineHas(line, wanted)) line,
    ];
  }

  static bool _lineHas(CartLine line, Iterable<String> wanted) {
    final have = [
      for (final word in AssistantIntentParser.words(
        '${line.title} ${line.variantTitle ?? ''}',
      ))
        AssistantIntentParser.singular(word),
    ];
    // Only berries match by ending ("berry" in "Blueberry"): "apple" must
    // not remove Pineapple, nor "melon" Watermelon.
    return wanted.every(
      (w) => have.any((h) => h == w || (w == 'berry' && h.endsWith(w))),
    );
  }

  AssistantReply _remove(RemoveIntent intent) {
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is empty, so there is nothing to remove.',
        suggestions: _startChips,
      );
    }
    final query = intent.query;
    if (query.isEmpty) {
      final example = shortName(cart.lines.first.title);
      return AssistantReply(
        example == null
            ? 'Tell me what to remove. ${_cartSummary()}'
            : 'Tell me what to remove, for example "Remove $example". '
                  '${_cartSummary()}',
        actions: const [OpenCartAction()],
        suggestions: _chips([
          _removeChip(cart.lines.first),
          _cartChip,
          _emptyCartChip,
        ]),
      );
    }
    final matches = _matchingLines(query);
    if (matches.isEmpty) {
      return AssistantReply(
        'I could not find $query in your cart. ${_cartSummary()}',
        actions: const [OpenCartAction()],
        suggestions: _chips([
          _removeChip(cart.lines.first),
          _cartChip,
          _checkoutChip,
        ]),
      );
    }

    final String done;
    final quantity = intent.quantity;
    if (quantity != null) {
      // A number takes units off the first matching line only.
      final line = matches.first;
      final taken = quantity < line.quantity ? quantity : line.quantity;
      cart.setQuantity(line.variantId, line.quantity - taken);
      done = 'Removed $taken × ${_lineName(line)} from your cart.';
    } else {
      for (final line in matches) {
        cart.remove(line.variantId);
      }
      done =
          'Removed ${_join([for (final l in matches) _lineName(l)])} '
          'from your cart.';
    }
    if (cart.isEmpty) {
      return AssistantReply(
        '$done Your cart is empty now.',
        actions: const [OpenCartAction()],
        suggestions: _startChips,
      );
    }
    return AssistantReply(
      '$done ${_cartSummary()}',
      actions: const [OpenCartAction()],
      suggestions: _chips([
        _checkoutChip,
        _cartChip,
        _removeChip(cart.lines.first),
      ]),
    );
  }

  /// Only asks: the cart is emptied by [ClearCartAction] after the
  /// shopper confirmed.
  AssistantReply _clearCart() {
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is already empty.',
        suggestions: _startChips,
      );
    }
    final count = cart.itemCount;
    return AssistantReply(
      count == 1
          ? 'This will remove the 1 item in your cart. Are you sure?'
          : 'This will remove all $count items from your cart. Are you '
                'sure?',
      actions: [
        ClearCartAction({
          for (final line in cart.lines) line.variantId: line.quantity,
        }),
        const OpenCartAction('Review cart'),
      ],
      suggestions: const [_cartChip, _checkoutChip, _offersChip],
    );
  }

  /// A typed yes or no to "Are you sure?". Only the button empties the
  /// cart, so a yes points to it.
  AssistantReply _answerClear(ClearCartAction pending, {required bool yes}) {
    if (!yes) {
      return const AssistantReply(
        'OK, I left your cart as it is.',
        actions: [OpenCartAction()],
        suggestions: [_cartChip, _checkoutChip, _offersChip],
      );
    }
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is already empty.',
        suggestions: _startChips,
      );
    }
    return AssistantReply(
      'To empty your cart, tap "${pending.label}" below.',
      actions: [pending, const OpenCartAction('Review cart')],
      suggestions: const [_cartChip, _checkoutChip, _offersChip],
    );
  }

  AssistantReply _checkout() {
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is empty, so there is nothing to check out yet. '
        'Ask me to add something first, for example "Add 2 cucumbers".',
        suggestions: [_offersChip, _berriesChip, 'Add 2 cucumbers'],
      );
    }
    return AssistantReply(
      '${_cartSummary()} Ready when you are.',
      actions: const [CheckoutAction(), OpenCartAction('Review cart')],
      suggestions: const [_paymentChip, _deliveryChip, _cartChip],
    );
  }

  AssistantReply _cart() {
    if (cart.isEmpty) {
      return const AssistantReply(
        'Your cart is empty.',
        actions: [OpenCartAction()],
        suggestions: _startChips,
      );
    }
    return AssistantReply(
      _cartSummary(),
      actions: const [OpenCartAction()],
      suggestions: _chips([
        _checkoutChip,
        _removeChip(cart.lines.first),
        _emptyCartChip,
      ]),
    );
  }

  AssistantReply _payment() => cart.isEmpty
      ? const AssistantReply(
          paymentText,
          suggestions: [_deliveryChip, _offersChip, _contactChip],
        )
      : const AssistantReply(
          paymentText,
          actions: [CheckoutAction()],
          suggestions: [_deliveryChip, _cartChip, _contactChip],
        );

  // ---- browsing ----------------------------------------------------------

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
      final ranked =
          [for (final (index, entry) in onSale.indexed) (index, entry)]
            ..sort((a, b) {
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
      final suggestions = _chips([
        _addChip(best.$2),
        _popularChip,
        _cartChip,
      ]);
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
        suggestions: suggestions,
        chipProducts: _chipsFor(suggestions, best.$2),
      );
    }

    final shown = bestDeals.take(maxProducts).toList();
    if (shown.isEmpty) {
      return AssistantReply(
        'I could not find any offers in the store right now.',
        actions: const [action],
        suggestions: [_popularChip, _categoriesChip, _fruitSaladChip],
      );
    }
    final pick = _firstAvailable(shown);
    final suggestions = _chips([
      _addChip(pick),
      _popularChip,
      _categoriesChip,
    ]);
    return AssistantReply(
      'Nothing is marked down right now. Here are products from '
      '${_deals.title}.',
      products: shown,
      actions: const [action],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, pick),
    );
  }

  /// A category tile ([category] set) or another store collection.
  Future<AssistantReply> _collection(
    String handle,
    String title, {
    CategoryEntry? category,
  }) async {
    final extra = handle == 'hampers'
        ? _giftActions
        : const <AssistantAction>[];
    final List<Product> products;
    try {
      products = await api.collectionProducts(handle, limit: maxProducts);
    } on HttpStatusException catch (e) {
      if (!e.isNotFound) rethrow;
      return AssistantReply(
        'I could not find $title in the store right now.',
        actions: extra,
        suggestions: [_categoriesChip, _offersChip, _fruitSaladChip],
      );
    }
    final action = OpenCollectionAction(
      'Open $title',
      handle: handle,
      title: title,
    );
    if (products.isEmpty) {
      return AssistantReply(
        '$title has no products in the store right now.',
        actions: [action, ...extra],
        suggestions: [_categoriesChip, _offersChip, _fruitSaladChip],
      );
    }
    final shown = products.take(maxProducts).toList();
    final pick = _firstAvailable(shown);
    final suggestions = _chips([
      if (category != null) _cheapestChip(category.label),
      _addChip(pick),
      _offersChip,
      _categoriesChip,
    ]);
    return AssistantReply(
      handle == 'hampers'
          ? 'A few gift ideas from Hampers. You can also open Flowers, '
                'Fruit Bouquets or Special Occasions below.'
          : 'A few products from $title:',
      products: shown,
      actions: [action, ...extra],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, pick),
    );
  }

  AssistantReply _allCategories() => AssistantReply(
    'Here are our categories.',
    actions: [
      for (final c in Catalog.categories)
        OpenCollectionAction(c.label, handle: c.handle, title: c.label),
      const OpenCategoriesAction(),
    ],
    suggestions: const [
      'Show local UAE produce',
      _popularChip,
      'Gift ideas',
      _offersChip,
    ],
  );

  AssistantReply _brands() => AssistantReply(
    'Here are the brands we love.',
    actions: [
      for (final brand in Catalog.brands)
        OpenSearchAction(brand.searchTerm, brand.name),
    ],
    suggestions: const [_popularChip, _categoriesChip, _offersChip],
  );

  /// Words about orders and accounts, which the store's search would
  /// answer with unrelated products.
  static const Set<String> _serviceWords = {
    'order',
    'orders',
    'minimum',
    'account',
    'accounts',
    'login',
    'logout',
    'signin',
    'signup',
    'password',
    'refund',
    'refunds',
    'invoice',
    'invoices',
    'receipt',
    'receipts',
    'history',
    'status',
  };

  Future<AssistantReply> _search(String query) async {
    if (query.isEmpty) {
      return const AssistantReply(
        'Tell me a product or a category and I will look in the store. '
        '$_tryHint',
      );
    }
    if (AssistantIntentParser.words(query).every(_serviceWords.contains)) {
      return const AssistantReply(
        'I cannot look up orders or accounts here. Customer service can '
        'help with that.',
        actions: contactActions,
        suggestions: [_deliveryChip, _paymentChip, _offersChip],
      );
    }
    // Only [maxProducts] rows are shown; "See all results" has the rest.
    final results = await _find(query, limit: maxProducts);
    if (results.isEmpty) return _notFound(query);
    final count = results.length;
    final shown = results.take(maxProducts).toList();
    final pick = _firstAvailable(shown);
    final suggestions = _chips([
      _cheapestChip(query),
      _stockChip(query),
      _addChip(pick),
    ]);
    return AssistantReply(
      count == 1
          ? 'I found this for "$query".'
          : 'Here is what I found for "$query".',
      products: shown,
      actions: [OpenSearchAction(query)],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, pick),
    );
  }

  // ---- price, stock, cheapest -------------------------------------------

  Future<AssistantReply> _cheapest(CheapestIntent intent) async {
    final query = intent.query;
    final max = intent.maxPriceCents;
    if (query.isEmpty) {
      return AssistantReply(
        max == null
            ? 'Tell me what to look for, for example "Cheapest avocado".'
            : 'Tell me what to look for under ${formatMoney(max)}, for '
                  'example "Avocado under ${max ~/ 100}".',
        suggestions: const ['Cheapest avocado', _offersChip, _categoriesChip],
      );
    }
    final found = await _find(query, limit: 20);
    if (found.isEmpty) return _notFound(query);
    final action = OpenSearchAction(query);
    // The store's search also suggests related products ("Guava" for
    // avocado): only the ones that name what was asked are ranked, unless
    // none does.
    final named = _naming(found, query);
    final exact = named.isNotEmpty;
    final results = exact ? named : found;

    int price(Product p) => p.defaultVariant!.priceCents;
    // Lowest price first; equal prices keep the store's order.
    final ranked =
        [
          for (final (index, product) in results.indexed)
            if (product.available) (index, product),
        ]..sort((a, b) {
          final byPrice = price(a.$2).compareTo(price(b.$2));
          return byPrice != 0 ? byPrice : a.$1.compareTo(b.$1);
        });
    final sorted = [for (final entry in ranked) entry.$2];
    if (sorted.isEmpty) {
      return AssistantReply(
        'Everything I found for "$query" is sold out right now.',
        products: results.take(maxProducts).toList(),
        actions: [action],
        suggestions: [_offersChip, _categoriesChip, _fruitSaladChip],
      );
    }
    final fitting = max == null
        ? sorted
        : sorted.where((p) => price(p) <= max).toList();
    if (fitting.isEmpty) {
      final cheapest = sorted.first;
      final suggestions = _chips([
        _addChip(cheapest),
        _offersChip,
        _categoriesChip,
      ]);
      return AssistantReply(
        'Nothing for "$query" is under ${formatMoney(max!)} right now. The '
        'cheapest is ${_name(cheapest, cheapest.defaultVariant!)} at '
        '${cheapest.defaultVariant!.priceText}.',
        products: [cheapest],
        actions: [action],
        suggestions: suggestions,
        chipProducts: _chipsFor(suggestions, cheapest),
      );
    }
    final shown = fitting.take(maxProducts).toList();
    final label = '${query[0].toUpperCase()}${query.substring(1)}';
    final suggestions = _chips([
      _addChip(shown.first),
      _priceChip(shown.first),
      _stockChip(query),
      _offersChip,
    ]);
    return AssistantReply(
      switch ((max, exact)) {
        (null, true) => 'The cheapest $query right now:',
        (null, false) => 'The cheapest of what I found for "$query":',
        (final int max, true) => '$label under ${formatMoney(max)}:',
        (final int max, false) =>
          'What I found for "$query" under ${formatMoney(max)}:',
      },
      products: shown,
      actions: [action],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, shown.first),
    );
  }

  /// [products] whose title, type, brand or tags contain every word of
  /// [query], as typed or made singular.
  static List<Product> _naming(List<Product> products, String query) {
    final wanted = AssistantIntentParser.words(query);
    if (wanted.isEmpty) return products;
    return [
      for (final product in products)
        if (_names(product, wanted)) product,
    ];
  }

  static bool _names(Product product, List<String> words) {
    final text = [
      product.title,
      product.productType,
      product.vendor,
      ...product.tags,
    ].join(' ').toLowerCase();
    return words.every(
      (word) =>
          text.contains(word) ||
          text.contains(AssistantIntentParser.singular(word)),
    );
  }

  /// [target]: the product of a "How much is ...?" chip, answered for
  /// itself instead of searching again.
  Future<AssistantReply> _price(String query, {Product? target}) async {
    if (query.isEmpty) {
      return const AssistantReply(
        'Tell me which product, for example "How much is avocado?".',
        suggestions: ['Cheapest avocado', _offersChip, _categoriesChip],
      );
    }
    final results = target != null
        ? [await _fresh(target)]
        : await _find(query, limit: maxProducts);
    if (results.isEmpty) return _notFound(query);
    final product = results.first;
    final variant = product.defaultVariant;
    final text = StringBuffer();
    if (variant == null) {
      text.write('${product.title} has no price in the store right now.');
    } else {
      text.write('${_name(product, variant)} is ${variant.priceText}');
      if (variant.onSale) {
        text.write(', down from ${formatMoney(variant.oldPriceCents!)}');
      }
      text.write('.');
      if (!variant.available) text.write(' It is sold out right now.');
      final others = [
        for (final v in product.variants)
          if (v.id != variant.id && v.available && v.label != null)
            '${v.label} is ${v.priceText}',
      ];
      if (others.isNotEmpty) text.write(' ${_join(others.take(2).toList())}.');
    }
    final suggestions = _chips([
      if (product.available) _addChip(product),
      _stockChip(query),
      _cheapestChip(query),
      _offersChip,
    ]);
    return AssistantReply(
      text.toString(),
      products: results.take(maxProducts).toList(),
      actions: [OpenSearchAction(query)],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, product),
    );
  }

  Future<AssistantReply> _stock(String query) async {
    if (query.isEmpty) {
      return const AssistantReply(
        'Tell me which product, for example "Is avocado in stock?".',
        suggestions: ['Cheapest avocado', _offersChip, _categoriesChip],
      );
    }
    final results = await _find(query, limit: maxProducts);
    if (results.isEmpty) return _notFound(query);
    final product = results.first;
    final String text;
    if (product.available) {
      final soldOut = [
        for (final v in product.variants)
          if (!v.available && v.label != null) v.label!,
      ];
      text = soldOut.isEmpty
          ? 'Yes, ${product.title} is in stock.'
          : 'Yes, ${product.title} is in stock. ${_join(soldOut)} '
                '${soldOut.length == 1 ? 'is' : 'are'} sold out right now.';
    } else {
      final other = _firstAvailable(results.skip(1));
      text = other == null
          ? '${product.title} is sold out right now.'
          : '${product.title} is sold out right now. ${other.title} is in '
                'stock.';
    }
    final suggestions = product.available
        ? _chips([
            _addChip(product),
            _priceChip(product),
            _cheapestChip(query),
          ])
        : _chips([_cheapestChip(query), _offersChip, _categoriesChip]);
    return AssistantReply(
      text,
      products: results.take(maxProducts).toList(),
      actions: [OpenSearchAction(query)],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, product),
    );
  }

  // ---- recipes -----------------------------------------------------------

  /// The two dishes after [recipe] in [AssistantIntentParser.recipes],
  /// then the third, for buttons and chips.
  static List<Recipe> _otherRecipes(Recipe recipe) {
    const all = AssistantIntentParser.recipes;
    final at = all.indexOf(recipe);
    return [for (var i = 1; i < all.length; i++) all[(at + i) % all.length]];
  }

  /// True when a word of [title] is [ingredient], singular or plural
  /// ("Tomatoes" has "tomato").
  static bool _titleHas(String title, String ingredient) {
    final wanted = AssistantIntentParser.singular(ingredient);
    return AssistantIntentParser.words(title).any(
      (w) => w == ingredient || AssistantIntentParser.singular(w) == wanted,
    );
  }

  /// Runs [task] for each of [items], at most [recipeSearchWidth] at a
  /// time. Results keep the order of [items].
  static Future<List<R?>> _pooled<T, R>(
    List<T> items,
    Future<R?> Function(T item) task,
  ) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < items.length) {
        final index = next++;
        results[index] = await task(items[index]);
      }
    }

    await Future.wait([
      for (var i = 0; i < recipeSearchWidth && i < items.length; i++) worker(),
    ]);
    return results;
  }

  Future<AssistantReply> _recipe(Recipe recipe) async {
    final found = await _pooled<String, Product>(recipe.ingredients, (
      ingredient,
    ) async {
      // The cheapest in stock that names the ingredient: the store often
      // lists a box first.
      final results = await _find(ingredient, limit: 10);
      return _cheapestAvailable(
        results.where((p) => _titleHas(p.title, ingredient)),
      );
    });
    final products = <Product>[];
    final missing = <String>[];
    for (final (index, product) in found.indexed) {
      if (product == null) {
        missing.add(recipe.ingredients[index]);
      } else if (!products.any((p) => p.id == product.id)) {
        products.add(product);
      }
    }
    final others = _otherRecipes(recipe);
    final otherButtons = [
      for (final other in others.take(2))
        SendMessageAction(other.label, message: other.message),
    ];
    if (products.isEmpty) {
      return AssistantReply(
        'I could not find the ingredients for ${recipe.dish} in stock right '
        'now.',
        actions: otherButtons,
        suggestions: [others[2].message, _offersChip, _categoriesChip],
      );
    }
    final shown = products.take(maxRecipeProducts).toList();
    final suggestions = _chips([
      _addChip(shown.first),
      _cartChip,
      others[2].message,
      _offersChip,
    ]);
    return AssistantReply(
      missing.isEmpty
          ? 'For ${recipe.dish}, you could use:'
          : 'For ${recipe.dish}, you could use these. I could not find '
                '${_join(missing)} in stock right now.',
      products: shown,
      actions: [
        AddProductsAction('Add all to cart', products: shown),
        ...otherButtons,
      ],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, shown.first),
    );
  }

  AssistantReply _recipeIdeas() {
    const all = AssistantIntentParser.recipes;
    return AssistantReply(
      'Here are some ideas. Pick one and I will find what you need in the '
      'store.',
      actions: [
        for (final recipe in all)
          SendMessageAction(recipe.label, message: recipe.message),
      ],
      suggestions: [all[0].message, all[3].message, _offersChip],
    );
  }

  // ---- favourites --------------------------------------------------------

  /// Today's copy of a saved product; the saved copy when the store
  /// cannot be asked, marked sold out when the store no longer has it.
  Future<Product> _fresh(Product saved) async {
    if (saved.handle.isEmpty) return saved;
    try {
      final product = await api.product(saved.handle);
      return product.id == saved.id ? product : saved;
    } on HttpStatusException catch (e) {
      return e.isNotFound ? saved.soldOut() : saved;
    } on ApiException {
      return saved;
    }
  }

  Future<AssistantReply> _favourites() async {
    final saved = favourites?.products ?? const <Product>[];
    if (saved.isEmpty) {
      return const AssistantReply(
        'You have no favourites yet. Tap the heart on a product page to '
        'save it, and it will show up here.',
        actions: [OpenCategoriesAction('Browse categories')],
        suggestions: [_popularChip, _categoriesChip, _offersChip],
      );
    }
    final shown = await Future.wait(saved.take(maxProducts).map(_fresh));
    final count = saved.length;
    final pick = _firstAvailable(shown);
    final suggestions = _chips([_addChip(pick), _cartChip, _popularChip]);
    return AssistantReply(
      count == 1
          ? 'You have 1 favourite.'
          : count <= maxProducts
          ? 'Here are your $count favourites.'
          : 'You have $count favourites. Here are the latest '
                '$maxProducts.',
      products: shown,
      actions: const [OpenFavouritesAction()],
      suggestions: suggestions,
      chipProducts: _chipsFor(suggestions, pick),
    );
  }
}
