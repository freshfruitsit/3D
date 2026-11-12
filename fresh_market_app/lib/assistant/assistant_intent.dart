import '../data/catalog.dart';

/// What the shopper asked the demo assistant for. Produced by
/// [AssistantIntentParser]; no network, no Flutter.
sealed class AssistantIntent {
  const AssistantIntent();
}

/// "Add 2 cucumbers": put [quantity] of the first product found for
/// [query] in the cart. [query] is empty when no product was named.
final class AddIntent extends AssistantIntent {
  const AddIntent({
    required this.quantity,
    required this.query,
    this.measureAsked = false,
    this.moreItems = false,
  });

  /// 1 to [AssistantIntentParser.maxAddQuantity].
  final int quantity;
  final String query;

  /// A weight or volume was asked for ("2kg", "half a kilo"). The cart
  /// holds whole packs, so nothing is added; the shopper picks the size.
  final bool measureAsked;

  /// A second product followed ("... and 3 bananas"); only the first one
  /// is in [query].
  final bool moreItems;

  @override
  String toString() => 'AddIntent($quantity, "$query")';
}

/// "Remove cucumbers from my cart", "empty my cart": the assistant cannot
/// do that.
final class RemoveIntent extends AssistantIntent {
  const RemoveIntent();
}

/// "Checkout", "pay".
final class CheckoutIntent extends AssistantIntent {
  const CheckoutIntent();
}

/// "Open my cart", "basket".
final class CartIntent extends AssistantIntent {
  const CartIntent();
}

/// "What is on offer?", "deals", "sale", "discounts".
final class OffersIntent extends AssistantIntent {
  const OffersIntent();
}

/// A catalogue category was named ("Show me berries").
final class CategoryIntent extends AssistantIntent {
  const CategoryIntent(this.category);

  /// One of [Catalog.categories].
  final CategoryEntry category;

  @override
  String toString() => 'CategoryIntent(${category.handle})';
}

/// Anything else: a product search for [query]. [query] is empty when the
/// message had no words to search for ("hi", "please").
final class SearchIntent extends AssistantIntent {
  const SearchIntent(this.query);

  final String query;

  @override
  String toString() => 'SearchIntent("$query")';
}

/// Turns a typed message into an [AssistantIntent] by keyword matching.
/// This is a script, not AI.
///
/// The message is lower-cased and punctuation is dropped, then the first
/// rule that matches wins:
///
/// 0. `remove` / `delete` / `empty` / `clear` -> [RemoveIntent]
/// 1. a command to add (`add ...`, a leading `buy ...`, `put ... in my
///    cart`) -> [AddIntent]. A question ("Where can I buy ...?"), a
///    negation ("Don't add ...") or `buy` in the middle of a sentence is
///    not a command and falls through to the rules below; with an offer
///    word ("Buy 1 get 1 free offers") it is [OffersIntent].
/// 2. `checkout` / `pay` -> [CheckoutIntent]
/// 3. `cart` / `basket` -> [CartIntent]
/// 4. `offer(s)` / `deal(s)` / `sale` / `discount(s)` -> [OffersIntent]
/// 5. a category word, when the message names nothing else ->
///    [CategoryIntent] ("orange juice" is a search, not Citrus)
/// 6. otherwise -> [SearchIntent] with the stop words removed
abstract final class AssistantIntentParser {
  /// The most units one "add" message can put in the cart.
  static const int maxAddQuantity = 20;

  /// Before a leading "buy" these still leave it a command.
  static const Set<String> _polite = {
    'please',
    'can',
    'could',
    'would',
    'you',
    'kindly',
    'just',
    'lets',
  };
  static const Set<String> _negations = {
    'dont',
    'not',
    'never',
    'wont',
    'cant',
    'shouldnt',
  };
  static const Set<String> _questionStarts = {
    'where',
    'how',
    'what',
    'whats',
    'which',
    'do',
    'does',
    'is',
    'are',
    'why',
    'when',
    'who',
    'should',
  };
  static const Set<String> _removeWords = {
    'remove',
    'delete',
    'empty',
    'clear',
  };

  /// Dropped from a search when an add word was not a command.
  static const Set<String> _commandFiller = {
    'add',
    'buy',
    'put',
    ..._negations,
    ..._questionStarts,
  };

  /// "2kg", "1.5 kg", "500 g", and any decimal number.
  static final RegExp _measure = RegExp(
    r'(?<![\p{L}\p{N}])\d+(?:[.,]\d+)?\s*(?:' +
        _unitPattern +
        r')(?![\p{L}\p{N}])|(?<![\p{L}\p{N}])\d+[.,]\d+(?![\p{L}\p{N}])',
    unicode: true,
  );
  static const String _unitPattern =
      'kilograms|kilogram|kilos|kilo|kgs|kg|grams|gram|gms|gm|g|ml|'
      'litres|litre|liters|liter|ltr|l|lbs|lb';
  static final Set<String> _unitWords = _unitPattern.split('|').toSet();
  static const Set<String> _fractionWords = {'half', 'quarter'};
  static final RegExp _timesBefore = RegExp(r'^(\d+)x$');
  static final RegExp _timesAfter = RegExp(r'^x(\d+)$');

  static const Set<String> _checkoutWords = {'checkout', 'pay'};
  static const Set<String> _cartWords = {'cart', 'basket'};
  static const Set<String> _offerWords = {
    'offer',
    'offers',
    'deal',
    'deals',
    'sale',
    'discount',
    'discounts',
  };

  static const Map<String, int> _numberWords = {
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
  };

  /// Words that say nothing about which product is wanted.
  static const Set<String> stopWords = {
    'show',
    'me',
    'the',
    'some',
    'find',
    'i',
    'want',
    'need',
    'please',
    'do',
    'you',
    'have',
    'any',
    'get',
    'a',
    'an',
    'of',
    'for',
    'to',
    'my',
    'can',
    'could',
    'would',
    'like',
    'looking',
    'look',
    'search',
    'is',
    'are',
    'there',
    'what',
    'whats',
    'which',
    'where',
    'in',
    'on',
    'with',
    'got',
    'give',
    'us',
    'we',
    'id',
    'im',
    'hi',
    'hello',
    'hey',
    'and',
    'your',
    'this',
    'that',
    'it',
    'today',
    'todays',
    'now',
    'open',
    'see',
    'list',
    'help',
    'thanks',
    'thank',
    'ok',
    'okay',
    'yes',
    'no',
  };

  /// Left out of an "add" message on top of [stopWords].
  static const Set<String> _addFiller = {
    'cart',
    'basket',
    'bag',
    'order',
    'into',
    'too',
    'also',
    'more',
    'x',
  };

  /// Ignored when deciding whether a message names only a category
  /// ("the fresh meat section").
  static const Set<String> _categoryFiller = {
    'fresh',
    'category',
    'categories',
    'section',
    'aisle',
    'products',
    'product',
    'items',
    'all',
    'shop',
    'browse',
  };

  /// Category word -> collection handle of a [Catalog.categories] tile.
  static const Map<String, String> categoryAliases = {
    'fruit': 'fruits',
    'fruits': 'fruits',
    'vegetable': 'vegetables',
    'vegetables': 'vegetables',
    'veg': 'vegetables',
    'veggies': 'vegetables',
    'meat': 'fresh-meat',
    'butchery': 'fresh-meat',
    'berries': 'berries',
    'flower': 'ambrosia-flowers',
    'flowers': 'ambrosia-flowers',
    'hamper': 'hampers',
    'hampers': 'hampers',
    'gift': 'hampers',
    'gifts': 'hampers',
    'citrus': 'citrus',
    'orange': 'citrus',
    'oranges': 'citrus',
    'lemon': 'citrus',
    'lemons': 'citrus',
    'mango': 'mangoes',
    'mangoes': 'mangoes',
    'mangos': 'mangoes',
    'melon': 'melons-pineapples',
    'melons': 'melons-pineapples',
    'pineapple': 'melons-pineapples',
    'tropical': 'tropical-exotic',
    'exotic': 'tropical-exotic',
    'greens': 'lettuce-greens',
    'lettuce': 'lettuce-greens',
    'salad': 'lettuce-greens',
    'herb': 'fresh-herbs',
    'herbs': 'fresh-herbs',
  };

  /// Lower-case words of [text]; punctuation is dropped (an apostrophe
  /// joins: "what's" -> "whats"), anything else that is not a letter or a
  /// digit separates words.
  static List<String> words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp("['’`]"), '')
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();

  static AssistantIntent parse(String text) {
    final tokens = words(text);
    final hasCart = tokens.any(_cartWords.contains);

    // 0. remove / empty: not something the assistant can do.
    final firstNamed = tokens.where((w) => !stopWords.contains(w)).firstOrNull;
    if (_removeWords.contains(firstNamed) ||
        (hasCart && tokens.any(_removeWords.contains)) ||
        (hasCart && tokens.contains('take') && tokens.contains('out'))) {
      return const RemoveIntent();
    }

    // 1. a command to add
    final addAt = _addTrigger(tokens);
    if (addAt >= 0) {
      if (tokens.any(_offerWords.contains) || tokens.contains('free')) {
        return const OffersIntent();
      }
      final command = !_questionStarts.contains(tokens.first) &&
          !tokens.take(addAt).any(_negations.contains);
      if (command) return _parseAdd(text);
    }

    // 2. checkout / pay ("check out" counts)
    if (tokens.any(_checkoutWords.contains) ||
        _hasPair(tokens, 'check', 'out')) {
      return const CheckoutIntent();
    }

    // 3. cart / basket
    if (hasCart) return const CartIntent();

    // 4. offers
    if (tokens.any(_offerWords.contains)) return const OffersIntent();

    final meaningful = tokens
        .where((w) => !stopWords.contains(w) && !_commandFiller.contains(w))
        .toList();

    // 5. a category, when nothing else is named
    final named =
        meaningful.where((w) => !_categoryFiller.contains(w)).toList();
    if (named.isNotEmpty && named.every(categoryAliases.containsKey)) {
      final handle = categoryAliases[named.first]!;
      return CategoryIntent(
        Catalog.categories.firstWhere((c) => c.handle == handle),
      );
    }

    // 6. product search
    return SearchIntent(meaningful.join(' '));
  }

  /// Index of the word that makes [tokens] an add command, or -1: `add`
  /// anywhere, `buy` only at the start (after "please", "can you"), and
  /// `put` / `get` only when a cart is named after it.
  static int _addTrigger(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final word = tokens[i];
      if (word == 'add') return i;
      if (word == 'buy' && tokens.take(i).every(_polite.contains)) return i;
      if ((word == 'put' || word == 'get') &&
          tokens.skip(i + 1).any(_cartWords.contains)) {
        return i;
      }
    }
    return -1;
  }

  static int? _quantity(String word) {
    final number = int.tryParse(word) ?? _numberWords[word];
    if (number != null) return number;
    if (word == 'dozen') return 12;
    final times = _timesBefore.firstMatch(word) ?? _timesAfter.firstMatch(word);
    return times == null ? null : int.tryParse(times.group(1)!);
  }

  static AddIntent _parseAdd(String text) {
    // Weights are taken out first: "1.5 kg" must not become 1 or 5 units.
    final lower = text.toLowerCase();
    var measure = _measure.hasMatch(lower);
    final tokens = words(lower.replaceAll(_measure, ' '));
    final rest = tokens.sublist(_addTrigger(tokens) + 1);

    var quantity = 1;
    var numberSeen = false;
    var moreItems = false;
    final product = <String>[];
    for (var i = 0; i < rest.length; i++) {
      final word = rest[i];
      if (_fractionWords.contains(word) || _unitWords.contains(word)) {
        measure = true;
        continue;
      }
      final number = _quantity(word);
      if (number != null && !numberSeen) {
        numberSeen = true;
        quantity = number.clamp(1, maxAddQuantity);
        continue;
      }
      if (product.isNotEmpty) {
        // A second item: "... 3 bananas", "... and 3 bananas", "... and
        // some bananas".
        final next = i + 1 < rest.length ? rest[i + 1] : null;
        final secondItem = int.tryParse(word) != null ||
            (word == 'and' &&
                next != null &&
                (_quantity(next) != null ||
                    const {'a', 'an', 'some'}.contains(next)));
        if (secondItem) {
          moreItems = true;
          break;
        }
      }
      if (stopWords.contains(word) || _addFiller.contains(word)) continue;
      product.add(word);
    }
    return AddIntent(
      quantity: quantity,
      query: product.join(' '),
      measureAsked: measure,
      moreItems: moreItems,
    );
  }

  static bool _hasPair(List<String> tokens, String first, String second) {
    for (var i = 0; i + 1 < tokens.length; i++) {
      if (tokens[i] == first && tokens[i + 1] == second) return true;
    }
    return false;
  }

  /// [query] with each plural word made singular ("cucumbers" ->
  /// "cucumber", "berries" -> "berry", "mangoes" -> "mango"). The store's
  /// search is tried with the words as typed first, then with this.
  static String singular(String query) =>
      query.split(' ').map(_singularWord).join(' ');

  static String _singularWord(String word) {
    if (word.length <= 3) return word;
    if (word.endsWith('ies')) {
      return '${word.substring(0, word.length - 3)}y';
    }
    if (word.endsWith('oes')) return word.substring(0, word.length - 2);
    if (word.endsWith('s') && !word.endsWith('ss') && !word.endsWith('us')) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }
}
