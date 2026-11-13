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

/// "Remove cucumbers", "remove 1 cucumber", "take the berries out of my
/// cart": take cart lines whose title matches [query] out of the cart.
final class RemoveIntent extends AssistantIntent {
  const RemoveIntent({this.query = '', this.quantity});

  /// Words of the product to remove; empty when none was named.
  final String query;

  /// Units to take off the first matching line; null removes every
  /// matching line completely.
  final int? quantity;

  @override
  String toString() => 'RemoveIntent(${quantity ?? 'all'}, "$query")';
}

/// "Empty my cart", "remove everything": only ever answered with a
/// question that asks the shopper to confirm.
final class ClearCartIntent extends AssistantIntent {
  const ClearCartIntent();
}

/// "Checkout", "pay".
final class CheckoutIntent extends AssistantIntent {
  const CheckoutIntent();
}

/// "Open my cart", "my basket".
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

/// A store collection that is not a category tile ("local produce",
/// "what's new", "birthday").
final class CollectionIntent extends AssistantIntent {
  const CollectionIntent(this.collection);

  /// One of [AssistantIntentParser.collections].
  final CollectionShortcut collection;

  @override
  String toString() => 'CollectionIntent(${collection.handle})';
}

/// "Show all categories", "what do you sell".
final class AllCategoriesIntent extends AssistantIntent {
  const AllCategoriesIntent();
}

/// "Cheapest avocado", "berries under 30 dhs": the lowest-priced products
/// in stock for [query], at most [maxPriceCents] when a limit was given.
final class CheapestIntent extends AssistantIntent {
  const CheapestIntent(this.query, {this.maxPriceCents});

  /// Empty when no product was named.
  final String query;
  final int? maxPriceCents;

  @override
  String toString() => 'CheapestIntent("$query", ${maxPriceCents ?? '-'})';
}

/// "How much is avocado?", "price of kiwi".
final class PriceIntent extends AssistantIntent {
  const PriceIntent(this.query);

  /// Empty when no product was named.
  final String query;

  @override
  String toString() => 'PriceIntent("$query")';
}

/// "Is avocado available?", "do you have kiwi in stock".
final class StockIntent extends AssistantIntent {
  const StockIntent(this.query);

  /// Empty when no product was named.
  final String query;

  @override
  String toString() => 'StockIntent("$query")';
}

/// "Ideas for a fruit salad": store products for [recipe].
final class RecipeIntent extends AssistantIntent {
  const RecipeIntent(this.recipe);

  /// One of [AssistantIntentParser.recipes].
  final Recipe recipe;

  @override
  String toString() => 'RecipeIntent(${recipe.name})';
}

/// "Recipe ideas", "what should I cook": the dishes to choose from.
final class RecipeIdeasIntent extends AssistantIntent {
  const RecipeIdeasIntent();
}

/// "My favourites", "wishlist".
final class FavouritesIntent extends AssistantIntent {
  const FavouritesIntent();
}

/// "Contact customer service", "phone number", "opening hours".
final class ContactIntent extends AssistantIntent {
  const ContactIntent();
}

/// "Payment methods", "cash on delivery", "apple pay".
final class PaymentIntent extends AssistantIntent {
  const PaymentIntent();
}

/// "Delivery", "when will it arrive", "delivery fee".
final class DeliveryIntent extends AssistantIntent {
  const DeliveryIntent();
}

/// A question about Express: "Is Express open?", "can I get it in 1
/// hour?", "express delivery". ("Show 1Hr Express" opens the collection.)
final class ExpressIntent extends AssistantIntent {
  const ExpressIntent();
}

/// "Brands", "which brands do you have".
final class BrandsIntent extends AssistantIntent {
  const BrandsIntent();
}

/// "Help", "what can you do", "menu", or a greeting ("hi").
final class HelpIntent extends AssistantIntent {
  const HelpIntent({this.greeting = false});

  /// Only a greeting, no request for help.
  final bool greeting;
}

/// "Thanks", "thank you", "bye".
final class ThanksIntent extends AssistantIntent {
  const ThanksIntent({this.farewell = false});

  /// The shopper said goodbye.
  final bool farewell;
}

/// Anything else: a product search for [query]. [query] is empty when the
/// message had no words to search for ("please", "show me").
final class SearchIntent extends AssistantIntent {
  const SearchIntent(this.query);

  final String query;

  @override
  String toString() => 'SearchIntent("$query")';
}

/// A store collection the assistant can open by name.
class CollectionShortcut {
  const CollectionShortcut(this.handle, this.title);

  final String handle;

  /// Title of the list it opens.
  final String title;
}

/// A dish the assistant suggests store products for. Scripted: the
/// ingredients are fixed words, the products and prices come from the
/// store.
class Recipe {
  const Recipe(
    this.name,
    this.ingredients, {
    required this.aliases,
    this.article = 'a ',
  });

  /// "fruit salad", "BBQ".
  final String name;

  /// Searched one by one in the store, singular words.
  final List<String> ingredients;

  /// Phrases that name the dish in a message, lower case.
  final List<String> aliases;

  /// "a " or "" before [name].
  final String article;

  /// "a fruit salad", "guacamole".
  String get dish => '$article$name';

  /// The message that asks for this dish: "Ideas for a fruit salad".
  String get message => 'Ideas for $dish';

  /// Button text: "Fruit salad ideas".
  String get label => '${name[0].toUpperCase()}${name.substring(1)} ideas';
}

/// Turns a typed message into an [AssistantIntent] by keyword matching.
/// This is a script, not AI.
///
/// The message is lower-cased and punctuation is dropped, then the first
/// rule that matches wins:
///
///  1. `empty` / `clear` (or `remove everything`) with nothing else named
///     -> [ClearCartIntent]
///  2. `remove` / `delete` first, or with a cart word, or `take ... out`
///     -> [RemoveIntent]
///  3. a command to add (`add ...`, a leading `buy ...` / `order ...`,
///     `put ... in my cart`) -> [AddIntent]. A question ("Where can I buy
///     ...?"), a negation ("Don't add ...") or `buy` in the middle of a
///     sentence is not a command and falls through to the rules below;
///     with only offer words ("Buy 1 get 1 free offers") it is
///     [OffersIntent], with a favourites word [FavouritesIntent]
///  4. customer service, phone, email, complaint, a late or missing order,
///     "where is my order" -> [ContactIntent]
///  5. payment methods, card, cash on delivery, Apple Pay, "how can I
///     pay" -> [PaymentIntent]
///     then Express or "1 hour" with a delivery word, a status word (open,
///     closed, available, area, time, ...) or as a question ("is", "can",
///     "when", ...) -> [ExpressIntent]
///  6. delivery / shipping / "when will it arrive" / "minimum order" ->
///     [DeliveryIntent]
///  7. `checkout` / `pay` -> [CheckoutIntent]
///  8. `cart`, or `basket` when it is not a product ("my basket", not
///     "fruit basket") -> [CartIntent]
///  9. favourites / wishlist / saved / "my list" -> [FavouritesIntent]
/// 10. `offer(s)` / `deal(s)` / `sale` / `discount(s)` -> [OffersIntent]
/// 11. store address, location, opening hours, "where are you" with
///     nothing else named -> [ContactIntent]
/// 12. thanks / bye with nothing else named -> [ThanksIntent]
/// 13. help / options / menu / a greeting with nothing else named ->
///     [HelpIntent]
/// 14. brands with nothing else named -> [BrandsIntent]
/// 15. cheapest / cheap / budget / "under 20 dhs" -> [CheapestIntent]
/// 16. "how much", price, cost -> [PriceIntent]
/// 17. in stock / available / sold out -> [StockIntent]
/// 18. a dish with recipe / ideas / make / cook / "for a" ->
///     [RecipeIntent]; "recipe ideas" alone -> [RecipeIdeasIntent]
/// 19. categories / browse / "what do you sell" -> [AllCategoriesIntent]
/// 20. collection or category words, when the message names nothing
///     else -> [CollectionIntent] or [CategoryIntent] ("orange juice" is
///     a search, not Citrus; "fruit platter" is Fruit Platters, not
///     Fruits)
/// 21. otherwise -> [SearchIntent] with the stop words removed
abstract final class AssistantIntentParser {
  /// The most units one "add" message can put in the cart.
  static const int maxAddQuantity = 20;

  /// Before a leading "buy" these still leave it a command.
  static const Set<String> _polite = {
    'please',
    'pls',
    'plz',
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
  static const Set<String> _removeWords = {'remove', 'delete'};
  static const Set<String> _clearWords = {'empty', 'clear'};

  /// Words that may stand next to [_clearWords] in "empty my cart".
  static const Set<String> _clearFiller = {
    ..._removeWords,
    ..._clearWords,
    'cart',
    'bag',
    'trolley',
    'all',
    'everything',
    'item',
    'items',
    'out',
    'take',
    'whole',
    'entire',
    'completely',
    'from',
    'off',
    'products',
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

  /// "basket" counts only where [_cartTokens] turned it into "cart".
  static const Set<String> _cartWords = {'cart'};

  /// Before "basket" these make it the shopping cart ("my basket", "add it
  /// to the basket"); after a product word it is a product ("fruit
  /// basket").
  static const Set<String> _basketLead = {
    'my',
    'the',
    'your',
    'shopping',
    'to',
    'in',
    'into',
    'from',
    'of',
    'open',
    'show',
    'view',
    'see',
    'check',
    'empty',
    'clear',
    'whole',
    'entire',
  };
  static const Set<String> _offerWords = {
    'offer',
    'offers',
    'deal',
    'deals',
    'sale',
    'discount',
    'discounts',
  };

  /// After a leading "order" these make it a question about an order
  /// ("order status"), not a command.
  static const Set<String> _orderQuestion = {
    'status',
    'track',
    'tracking',
    'history',
    'number',
    'cancel',
    'my',
    'late',
    'missing',
    'problem',
    'issue',
    'delivered',
    'arrive',
    'placed',
    'previous',
    'last',
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
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
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
    'pls',
    'plz',
    // Courtesy words of Gulf English.
    'habibi',
    'habibti',
    'yalla',
    'yallah',
    'wallah',
    'wallahi',
    'inshallah',
    'mashallah',
    'khalas',
    'salam',
    'salaam',
    'ahlan',
    // "Do you sell / carry chiquita bananas?"
    'sell',
    'selling',
    'carry',
  };

  /// Left out of an "add" message on top of [stopWords].
  static const Set<String> _addFiller = {
    'cart',
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

  /// Also ignored when deciding whether a message names only collections
  /// ("local UAE produce", "gift ideas").
  static const Set<String> _collectionFiller = {
    'produce',
    'range',
    'collection',
    'collections',
    'stuff',
    'things',
    'goods',
    'selection',
    'from',
    'idea',
    'ideas',
    'option',
    'options',
    'choices',
    'food',
    'foods',
    'only',
    'store',
    'anything',
    'something',
    'else',
    'item',
    'available',
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

  static const CollectionShortcut localUae = CollectionShortcut(
    Catalog.localHandle,
    Catalog.localTitle,
  );
  static const CollectionShortcut organic = CollectionShortcut(
    'organic-food',
    'Organic Food',
  );
  static const CollectionShortcut newArrivals = CollectionShortcut(
    'new-arrivals',
    'New Arrivals',
  );
  static const CollectionShortcut bestSellers = CollectionShortcut(
    'best-sellers',
    'Best Sellers',
  );
  static const CollectionShortcut trending = CollectionShortcut(
    'trending',
    'Trending This Week',
  );
  static const CollectionShortcut express = CollectionShortcut(
    'express',
    '1Hr Express',
  );
  static const CollectionShortcut bulkBuy = CollectionShortcut(
    'bulk-buy',
    'Bulk Buy',
  );
  static const CollectionShortcut dairy = CollectionShortcut('dairy', 'Dairy');
  static const CollectionShortcut eggsCheese = CollectionShortcut(
    'eggs-cheese',
    'Eggs & Cheese',
  );
  static const CollectionShortcut dates = CollectionShortcut('dates', 'Dates');
  static const CollectionShortcut nuts = CollectionShortcut(
    'nuts-dried-fruits',
    'Nuts & Dried Fruits',
  );
  static const CollectionShortcut healthyPouches = CollectionShortcut(
    'healthy-pouches',
    'Healthy Pouches',
  );
  static const CollectionShortcut platters = CollectionShortcut(
    'ambrosia-platters',
    'Fruit Platters',
  );
  static const CollectionShortcut bouquets = CollectionShortcut(
    'ambrosia-bouquets',
    'Fruit Bouquets',
  );
  static const CollectionShortcut occasions = CollectionShortcut(
    'ambrosia-occasions',
    'Special Occasions',
  );
  static const CollectionShortcut eid = CollectionShortcut(
    'ambrosia-eid',
    'Eid',
  );
  static const CollectionShortcut ramadan = CollectionShortcut(
    'ambrosia-ramadan',
    'Ramadan',
  );
  static const CollectionShortcut christmas = CollectionShortcut(
    'ambrosia-christmas',
    'Christmas',
  );
  static const CollectionShortcut valentines = CollectionShortcut(
    'ambrosia-valentines',
    "Valentine's Day",
  );
  static const CollectionShortcut mothersDay = CollectionShortcut(
    'ambrosia-mothers-day',
    "Women's & Mother's Day",
  );

  /// Every collection [CollectionIntent] can open.
  static const List<CollectionShortcut> collections = [
    localUae,
    organic,
    newArrivals,
    bestSellers,
    trending,
    express,
    bulkBuy,
    dairy,
    eggsCheese,
    dates,
    nuts,
    healthyPouches,
    platters,
    bouquets,
    occasions,
    eid,
    ramadan,
    christmas,
    valentines,
    mothersDay,
  ];

  /// One word -> collection. Checked after [_collectionPhrases].
  static const Map<String, CollectionShortcut> collectionAliases = {
    'local': localUae,
    'uae': localUae,
    'emirati': localUae,
    'organic': organic,
    'new': newArrivals,
    'latest': newArrivals,
    'arrivals': newArrivals,
    'popular': bestSellers,
    'bestsellers': bestSellers,
    'bestseller': bestSellers,
    'bestselling': bestSellers,
    'top': bestSellers,
    'recommend': bestSellers,
    'recommended': bestSellers,
    'recommendation': bestSellers,
    'recommendations': bestSellers,
    'trending': trending,
    'express': express,
    '1hr': express,
    'fast': express,
    'quick': express,
    'urgent': express,
    'bulk': bulkBuy,
    'wholesale': bulkBuy,
    'dairy': dairy,
    'milk': dairy,
    'eggs': eggsCheese,
    'egg': eggsCheese,
    'cheese': eggsCheese,
    'dates': dates,
    'nuts': nuts,
    'nut': nuts,
    'healthy': healthyPouches,
    'pouches': healthyPouches,
    'pouch': healthyPouches,
    'snacks': healthyPouches,
    'snack': healthyPouches,
    'platter': platters,
    'platters': platters,
    'bouquet': bouquets,
    'bouquets': bouquets,
    'birthday': occasions,
    'birthdays': occasions,
    'anniversary': occasions,
    'wedding': occasions,
    'party': occasions,
    'parties': occasions,
    'celebration': occasions,
    'celebrations': occasions,
    'occasion': occasions,
    'occasions': occasions,
    'eid': eid,
    'ramadan': ramadan,
    'iftar': ramadan,
    'christmas': christmas,
    'xmas': christmas,
    'valentine': valentines,
    'valentines': valentines,
    'mum': mothersDay,
    'mom': mothersDay,
    'mother': mothersDay,
    'mothers': mothersDay,
  };

  /// Two or three words -> a collection handle, or a category handle
  /// ("flower bouquet" is Flowers). Stop words are already gone, so
  /// "made in uae" is `made uae`.
  static const Map<String, String> _collectionPhrases = {
    'made uae': 'local-uae',
    'new arrivals': 'new-arrivals',
    'new arrival': 'new-arrivals',
    'best sellers': 'best-sellers',
    'best seller': 'best-sellers',
    'best selling': 'best-sellers',
    'top sellers': 'best-sellers',
    'top selling': 'best-sellers',
    'most popular': 'best-sellers',
    '1 hour': 'express',
    'one hour': 'express',
    '1 hr': 'express',
    'dried fruit': 'nuts-dried-fruits',
    'dried fruits': 'nuts-dried-fruits',
    'party platter': 'ambrosia-platters',
    'party platters': 'ambrosia-platters',
    'fruit platter': 'ambrosia-platters',
    'fruit platters': 'ambrosia-platters',
    'flower bouquet': 'ambrosia-flowers',
    'flower bouquets': 'ambrosia-flowers',
    'flowers bouquet': 'ambrosia-flowers',
    'mothers day': 'ambrosia-mothers-day',
    'mother day': 'ambrosia-mothers-day',
    'womens day': 'ambrosia-mothers-day',
    'women day': 'ambrosia-mothers-day',
    'valentines day': 'ambrosia-valentines',
    'valentine day': 'ambrosia-valentines',
  };

  /// In a cart-free "buy ..." these name a collection, not a product
  /// ("buy in bulk", "buy local").
  static const Set<String> _collectionCommands = {
    'bulk',
    'wholesale',
    'local',
    'uae',
    'emirati',
    'organic',
  };

  // ---- recipes -----------------------------------------------------------

  /// The dishes the assistant has ideas for, in the order they are
  /// offered.
  static const List<Recipe> recipes = [
    Recipe(
      'fruit salad',
      ['strawberry', 'kiwi', 'banana', 'blueberry'],
      aliases: ['fruit salad', 'fruits salad', 'fruit salads'],
    ),
    Recipe(
      'smoothie',
      ['banana', 'blueberry', 'strawberry', 'mango'],
      aliases: ['smoothie', 'smoothies', 'smoothy'],
    ),
    Recipe(
      'green salad',
      ['lettuce', 'cucumber', 'tomato', 'capsicum'],
      aliases: ['green salad', 'garden salad', 'salad', 'salads'],
    ),
    Recipe(
      'guacamole',
      ['avocado', 'tomato', 'onion', 'lime'],
      aliases: ['guacamole', 'guac'],
      article: '',
    ),
    Recipe(
      'BBQ',
      ['kofta', 'tawouk', 'corn', 'tomato'],
      aliases: ['bbq', 'bbqs', 'barbecue', 'barbeque', 'grill', 'grilling'],
    ),
    Recipe(
      'breakfast',
      ['banana', 'blueberry', 'raspberry', 'kiwi'],
      aliases: ['breakfast', 'brunch'],
      article: '',
    ),
  ];

  /// With a dish named, these ask for its ingredients.
  static const Set<String> _dishTriggers = {
    'recipe',
    'recipes',
    'idea',
    'ideas',
    'make',
    'making',
    'cook',
    'cooking',
    'prepare',
    'preparing',
    'ingredient',
    'ingredients',
    'recommend',
    'suggest',
    'suggestion',
    'suggestions',
    'inspiration',
  };

  /// Alone (with [_ideasFiller]) these ask for the list of dishes.
  static const Set<String> _ideasTriggers = {
    'recipe',
    'recipes',
    'idea',
    'ideas',
    'cook',
    'cooking',
    'make',
    'inspiration',
    'meal',
    'meals',
  };
  static const Set<String> _ideasFiller = {
    ..._ideasTriggers,
    'making',
    'dinner',
    'lunch',
    'tonight',
    'dish',
    'dishes',
    'something',
    'anything',
    'food',
    'easy',
    'quick',
    'simple',
    'healthy',
    'new',
    'good',
    'tasty',
    'nice',
    'few',
    'more',
    'other',
    'suggest',
    'suggestion',
    'suggestions',
    'will',
    'shall',
    'recommend',
  };

  /// Between "for" and a dish ("for a BBQ", "for my breakfast").
  static const Set<String> _determiners = {
    'a',
    'an',
    'my',
    'the',
    'some',
    'our',
  };

  // ---- contact, payment, delivery ---------------------------------------

  static const Set<String> _contactWords = {
    'contact',
    'phone',
    'telephone',
    'call',
    'email',
    'mail',
    'whatsapp',
    'complaint',
    'complaints',
    'complain',
    'refund',
    'refunds',
    'helpline',
    'hotline',
    'agent',
    'human',
    'representative',
    'careline',
    'feedback',
    'tracking',
  };
  static const List<String> _contactPhrases = [
    'customer service',
    'customer care',
    'customer support',
    'customer services',
    'talk to',
    'talk with',
    'speak to',
    'speak with',
    'in touch',
    'reach you',
    'order status',
  ];
  static const Set<String> _issueWords = {
    'late',
    'missing',
    'wrong',
    'damaged',
    'problem',
    'problems',
    'issue',
    'issues',
    'delayed',
    'broken',
    'rotten',
    'spoiled',
    'spoilt',
    'cancel',
    'cancelled',
    'canceled',
    'track',
  };
  static const Set<String> _orderWords = {
    'order',
    'orders',
    'delivery',
    'delivered',
    'item',
    'items',
    'product',
    'products',
    'driver',
    'rider',
    'package',
    'parcel',
  };
  static const Set<String> _notYet = {
    'didnt',
    'hasnt',
    'havent',
    'not',
    'never',
    'still',
    'yet',
  };
  static const Set<String> _arrived = {
    'arrived',
    'arrive',
    'delivered',
    'came',
    'come',
    'received',
    'receive',
  };

  /// Need nothing else named to mean the store's contact details.
  static const Set<String> _weakContactWords = {
    'support',
    'number',
    'address',
    'location',
    'located',
    'hours',
    'timings',
    'timing',
    'branch',
    'branches',
    'outlet',
    'outlets',
  };
  static const Set<String> _openWords = {
    'open',
    'opening',
    'close',
    'closing',
    'closed',
  };
  static const Set<String> _contactFiller = {
    ..._weakContactWords,
    ..._openWords,
    'store',
    'shop',
    'stores',
    'shops',
    'fresh',
    'market',
    'working',
    'business',
    'office',
    'main',
    'customer',
    'based',
    'visit',
    'physical',
    'contact',
    'details',
    'detail',
    'info',
    'information',
    'time',
    'times',
    'near',
    'nearest',
    'exact',
    'full',
    'will',
    'be',
    'tomorrow',
  };

  static const Set<String> _paymentWords = {
    'payment',
    'payments',
    'cod',
    'visa',
    'mastercard',
    'amex',
    'paypal',
    'tabby',
    'tamara',
    'applepay',
    'gpay',
    'installments',
    'instalments',
  };

  /// Payment words only when no greeting card is meant.
  static const Set<String> _cardWords = {
    'card',
    'cards',
    'cash',
    'credit',
    'debit',
  };
  static const Set<String> _greetingCard = {
    'gift',
    'greeting',
    'greetings',
    'birthday',
    'message',
    'note',
    'anniversary',
    'wedding',
    'eid',
    'christmas',
    'valentine',
    'valentines',
    'ramadan',
  };

  /// After "pay" these ask how to pay, not to pay now.
  static const Set<String> _payHow = {
    'by',
    'with',
    'using',
    'via',
    'on',
    'through',
    'online',
    'method',
    'methods',
    'option',
    'options',
    'ways',
    'way',
    'accept',
    'accepted',
  };

  static const Set<String> _deliveryWords = {
    'delivery',
    'deliveries',
    'deliver',
    'delivers',
    'delivering',
    'delivered',
    'shipping',
    'ship',
    'ships',
    'shipment',
    'dispatch',
    'courier',
    'arrive',
    'arrives',
    'arrival',
    'arriving',
  };

  // ---- favourites, thanks, help, brands ---------------------------------

  static const Set<String> _favouriteWords = {
    'favourite',
    'favourites',
    'favorite',
    'favorites',
    'fav',
    'favs',
    'fave',
    'faves',
    'wishlist',
    'wishlists',
    'saved',
    'liked',
    'hearted',
  };

  static const Set<String> _thanksWords = {
    'thanks',
    'thank',
    'thx',
    'thnx',
    'ty',
    'cheers',
    'appreciated',
    'appreciate',
    'shukran',
  };
  static const Set<String> _byeWords = {
    'bye',
    'goodbye',
    'byebye',
    'cya',
    'goodnight',
    'khalas',
  };
  static const Set<String> _thanksFiller = {
    ..._thanksWords,
    ..._byeWords,
    'so',
    'much',
    'very',
    'lot',
    'lots',
    'alot',
    'great',
    'perfect',
    'awesome',
    'cool',
    'nice',
    'good',
    'see',
    'later',
    'again',
    'help',
    'all',
    'thats',
    'will',
    'done',
    'its',
    'fine',
    'day',
    'night',
    'wonderful',
    'mate',
    'buddy',
    'dear',
    'assistant',
    'bot',
    'soon',
    'enough',
    'everything',
    'was',
    'helpful',
    'really',
  };

  static const Set<String> _greetWords = {
    'hi',
    'hello',
    'hey',
    'hiya',
    'howdy',
    'greetings',
    'salam',
    'salaam',
    'marhaba',
    'hola',
    'yo',
    'morning',
    'afternoon',
    'evening',
  };
  static const Set<String> _helpWords = {
    'help',
    'options',
    'option',
    'menu',
    'commands',
    'assist',
    'assistance',
    'start',
  };
  static const List<String> _helpPhrases = [
    'what can you do',
    'what do you do',
    'what can i ask',
    'what can i do',
    'how does this work',
    'how does it work',
    'how do you work',
    'how can you help',
    'how can you assist',
    'who are you',
    'what are you',
  ];
  static const Set<String> _helpFiller = {
    ..._greetWords,
    ..._helpWords,
    'there',
    'assistant',
    'bot',
    'good',
    'everyone',
    'all',
    'again',
    'guys',
    'dear',
    'friend',
    'team',
    'fresh',
    'market',
    'assalamu',
    'assalam',
    'alaikum',
    'alaykum',
    'wa',
    'something',
    'anything',
    'else',
    'ask',
    'work',
    'works',
    'this',
    'does',
    'out',
    'available',
  };

  static const Set<String> _brandWords = {'brand', 'brands'};
  static const Set<String> _brandFiller = {
    ..._brandWords,
    'sell',
    'selling',
    'carry',
    'stock',
    'stocked',
    'love',
    'loved',
    'top',
    'popular',
    'best',
    'available',
    'all',
    'our',
    'kind',
    'kinds',
    'type',
    'types',
    'different',
    'favourite',
    'favorite',
  };

  // ---- cheapest, price, stock -------------------------------------------

  static const Set<String> _cheapWords = {
    'cheapest',
    'cheap',
    'cheaper',
    'budget',
    'affordable',
    'inexpensive',
    'economical',
    'lowest',
    'bargain',
  };
  static const List<String> _cheapPhrases = [
    'least expensive',
    'low price',
    'low cost',
    'best price',
  ];
  static const String _currency = r'(?:aed|dhs|dh|dirhams|dirham)';

  /// "under 20", "below dhs 30", "less than 15.5 aed", "budget of 50",
  /// "20 aed or less". Group 1 or 2 holds the amount.
  static final RegExp _priceLimit = RegExp(
    '(?<![a-z])(?:under|below|less than|cheaper than|lower than|maximum|'
    'max|up to|upto|at most|no more than|not more than|budget of|budget)'
    '\\s*(?:$_currency\\.?\\s*)?(\\d+(?:[.,]\\d{1,2})?)'
    '(?:\\s*$_currency(?![a-z]))?'
    '|(?<![\\d.,])(\\d+(?:[.,]\\d{1,2})?)\\s*$_currency\\.?\\s+or\\s+'
    '(?:less|under|below)',
  );
  static const Set<String> _cheapFiller = {
    ..._cheapWords,
    'least',
    'expensive',
    'low',
    'price',
    'prices',
    'priced',
    'cost',
    'best',
    'option',
    'options',
    'one',
    'ones',
    'under',
    'below',
    'less',
    'than',
    'max',
    'maximum',
    'up',
    'upto',
    'most',
    'aed',
    'dhs',
    'dh',
    'dirham',
    'dirhams',
    'products',
    'product',
    'items',
    'available',
    'right',
    'only',
    'something',
    'anything',
  };

  static const Set<String> _priceWords = {
    'price',
    'prices',
    'priced',
    'pricing',
    'cost',
    'costs',
    'costing',
  };
  static const Set<String> _priceFiller = {
    ..._priceWords,
    'much',
    'does',
    'per',
    'each',
    'current',
    'currently',
    'kg',
    'kilo',
    'unit',
    'piece',
    'will',
    'be',
  };

  static const Set<String> _stockWords = {
    'stock',
    'instock',
    'available',
    'availability',
    'unavailable',
    'restock',
    'restocked',
  };
  static const Set<String> _stockFiller = {
    ..._stockWords,
    'sold',
    'out',
    'still',
    'currently',
    'right',
    'back',
    'yet',
    'again',
    'will',
    'be',
    'does',
    'they',
    'them',
    'left',
  };

  // ---- all categories ----------------------------------------------------

  static const Set<String> _allCategoriesWords = {
    'categories',
    'category',
    'departments',
    'department',
    'sections',
    'aisles',
    'catalogue',
    'catalog',
    'browse',
    'sell',
    'selling',
  };
  static const List<String> _allCategoriesPhrases = [
    'what do you have',
    'what have you got',
    'what you have',
    'what do you got',
  ];
  static final Set<String> _allCategoriesFiller = {
    ..._categoryFiller,
    ..._allCategoriesWords,
    'range',
    'store',
    'everything',
    'kinds',
    'kind',
    'types',
    'type',
    'main',
    'stuff',
    'things',
    'here',
    'available',
    'other',
  };

  /// Words that steer [parse] towards a rule.
  static final Set<String> _steering = {
    ..._removeWords,
    ..._clearWords,
    ..._cartWords,
    ..._checkoutWords,
    ..._offerWords,
    ..._unitWords,
    ..._fractionWords,
    ..._negations,
    ..._questionStarts,
    ..._numberWords.keys,
    ..._favouriteWords,
    ..._contactWords,
    ..._issueWords,
    ..._weakContactWords,
    ..._paymentWords,
    ..._cardWords,
    ..._deliveryWords,
    ..._cheapWords,
    ..._priceWords,
    ..._stockWords,
    ..._brandWords,
    ..._thanksWords,
    ..._byeWords,
    ..._greetWords,
    ..._helpWords,
    'free',
    'add',
    'buy',
    'put',
    'order',
    'take',
    'out',
    'more',
    'and',
    'x',
    'dozen',
    'wish',
    'much',
    'sold',
    'ingredient',
    'ingredients',
    'recipe',
    'recipes',
  };

  /// False for a word that would change what a message means when put
  /// into it (a command, a cart, offer, payment or delivery word, a
  /// number or a size). A product name shown in a suggestion keeps only
  /// plain words, so `Add 1 <name>` always parses as an add.
  static bool isPlainWord(String word) =>
      word.isNotEmpty &&
      !word.contains(RegExp(r'\d')) &&
      !stopWords.contains(word) &&
      !_steering.contains(word);

  /// Lower-case words of [text]; punctuation is dropped (an apostrophe
  /// joins: "what's" -> "whats"), anything else that is not a letter or a
  /// digit separates words.
  static List<String> words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp("['’`]"), '')
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();

  /// [tokens] with each "basket" that means the shopping cart turned into
  /// "cart": the first word, or after [_basketLead] ("my basket", "to a
  /// basket"). "fruit basket" and "gift basket" stay products.
  static List<String> _cartTokens(List<String> tokens) => [
    for (var i = 0; i < tokens.length; i++)
      tokens[i] == 'basket' && _basketIsCart(tokens, i) ? 'cart' : tokens[i],
  ];

  static bool _basketIsCart(List<String> tokens, int at) {
    if (at == 0) return true;
    final before = tokens[at - 1];
    if (_basketLead.contains(before)) return true;
    return before == 'a' &&
        at >= 2 &&
        const {'to', 'in', 'into'}.contains(tokens[at - 2]);
  }

  /// "Buy 1 get 1 free (offers)": only offer words, numbers and stop
  /// words besides the command.
  static bool _onlyOffer(String word) =>
      stopWords.contains(word) ||
      _offerWords.contains(word) ||
      const {'add', 'buy', 'get', 'free', 'order'}.contains(word) ||
      _quantity(word) != null;

  static const Set<String> _yesWords = {
    'yes',
    'yeah',
    'yea',
    'yep',
    'yup',
    'ya',
    'sure',
    'ok',
    'okay',
    'confirm',
    'confirmed',
    'absolutely',
    'definitely',
  };
  static const Set<String> _noWords = {
    'no',
    'nope',
    'nah',
    'cancel',
    'dont',
    'stop',
    'keep',
    'wait',
  };

  /// Around a yes or a no to "Are you sure?" ("yes, empty it", "no, keep
  /// my cart").
  static const Set<String> _answerFiller = {
    ..._clearFiller,
    'please',
    'pls',
    'it',
    'my',
    'the',
    'i',
    'am',
    'im',
    'do',
    'go',
    'ahead',
    'of',
    'course',
    'thanks',
    'thank',
    'you',
    'that',
    'them',
    'mind',
    'never',
    'now',
    'not',
    'just',
    'want',
    'to',
  };

  /// The shopper's answer to "Are you sure?": true for yes ("yes", "ok,
  /// empty it", "go ahead"), false for no ("no", "cancel", "keep it"),
  /// null for anything else (a new request).
  static bool? confirmation(String text) {
    final tokens = _cartTokens(words(text));
    if (tokens.isEmpty) return null;
    final yes =
        tokens.any(_yesWords.contains) ||
        _hasPhrase(tokens, 'do it') ||
        _hasPhrase(tokens, 'go ahead');
    final no =
        tokens.any(_noWords.contains) ||
        _hasPhrase(tokens, 'never mind') ||
        _hasPhrase(tokens, 'not now');
    if (yes == no) return null;
    final onlyAnswer = tokens.every(
      (w) =>
          _answerFiller.contains(w) ||
          _yesWords.contains(w) ||
          _noWords.contains(w),
    );
    return onlyAnswer ? yes : null;
  }

  static AssistantIntent parse(String text) {
    final tokens = _cartTokens(words(text));
    final hasCart = tokens.any(_cartWords.contains);
    final named = tokens.where((w) => !stopWords.contains(w)).toList();
    final firstNamed = named.firstOrNull;
    // Words that could name a product.
    final meaningful = tokens
        .where((w) => !stopWords.contains(w) && !_commandFiller.contains(w))
        .toList();

    // 1. empty the cart (always asked to confirm)
    final clearAsked =
        tokens.any(_clearWords.contains) ||
        (tokens.any((w) => _removeWords.contains(w) || w == 'take') &&
            tokens.any((w) => w == 'everything' || w == 'all'));
    // "Is my cart empty?" is a question, not a command.
    final question =
        tokens.isNotEmpty && _questionStarts.contains(tokens.first);
    if (clearAsked &&
        !question &&
        named.isNotEmpty &&
        named.every(_clearFiller.contains)) {
      return const ClearCartIntent();
    }

    // 2. remove from the cart
    final takeOut =
        tokens.contains('take') &&
        tokens.contains('out') &&
        (hasCart || firstNamed == 'take');
    if (_removeWords.contains(firstNamed) ||
        (hasCart && tokens.any(_removeWords.contains)) ||
        takeOut ||
        _hasPhrase(tokens, 'get rid of')) {
      // Favourites are changed with the heart, never from the cart.
      if (tokens.any(_favouriteWords.contains)) return const FavouritesIntent();
      return _parseRemove(text);
    }

    // 3. a command to add
    final addAt = _addTrigger(tokens);
    if (addAt >= 0) {
      // "Buy 1 get 1 free" asks for offers; "add 2 cucumbers and show me
      // offers" still adds.
      if ((tokens.any(_offerWords.contains) || tokens.contains('free')) &&
          tokens.every(_onlyOffer)) {
        return const OffersIntent();
      }
      final command =
          !_questionStarts.contains(tokens.first) &&
          !tokens.take(addAt).any(_negations.contains);
      if (command) {
        if (tokens.any(_favouriteWords.contains) ||
            _hasPhrase(tokens, 'wish list')) {
          return const FavouritesIntent();
        }
        final recipe = _findRecipe(tokens);
        if (recipe != null &&
            tokens.any(
              (w) => const {
                'ingredients',
                'ingredient',
                'recipe',
                'everything',
              }.contains(w),
            )) {
          return RecipeIntent(recipe.$1);
        }
        final add = _parseAdd(text);
        final addWords = add.query.split(' ');
        if (!hasCart &&
            add.query.isNotEmpty &&
            addWords.every(_collectionCommands.contains)) {
          return CollectionIntent(collectionAliases[addWords.first]!);
        }
        return add;
      }
    }

    // 4. customer service, complaints, a late order
    if (_isContact(tokens)) return const ContactIntent();

    // 5. payment methods
    if (_isPayment(tokens)) return const PaymentIntent();

    // 5b. Express questions ("is express open?", "1 hour delivery")
    if (_asksExpress(tokens)) return const ExpressIntent();

    // 6. delivery ("is there a minimum order?": checkout shows any fees)
    if (tokens.any(_deliveryWords.contains) ||
        _hasPhrase(tokens, 'same day') ||
        (tokens.contains('minimum') &&
            tokens.any(
              const {
                'order',
                'orders',
                'spend',
                'purchase',
                'amount',
                'cart',
                'value',
              }.contains,
            )) ||
        (tokens.contains('address') &&
            tokens.any(
              const {'my', 'change', 'update', 'new', 'different'}.contains,
            ))) {
      return const DeliveryIntent();
    }

    // 7. checkout / pay ("check out" counts)
    if (tokens.any(_checkoutWords.contains) ||
        _hasPhrase(tokens, 'check out')) {
      return const CheckoutIntent();
    }

    // 8. cart / basket
    if (hasCart) return const CartIntent();

    // 9. favourites
    if (!tokens.any(_brandWords.contains) &&
        (tokens.any(_favouriteWords.contains) ||
            _hasPhrase(tokens, 'wish list') ||
            _hasPhrase(tokens, 'my list'))) {
      return const FavouritesIntent();
    }

    // 10. offers
    if (tokens.any(_offerWords.contains)) return const OffersIntent();

    // 11. where the store is, when it is open
    final contactAsked =
        tokens.any(_weakContactWords.contains) ||
        (tokens.any(_openWords.contains) &&
            tokens.any(
              const {
                'when',
                'time',
                'times',
                'hours',
                'today',
                'now',
                'tomorrow',
                'you',
                'store',
                'shop',
              }.contains,
            )) ||
        (tokens.contains('where') &&
            tokens.any(
              const {'store', 'shop', 'you', 'located', 'based'}.contains,
            ));
    if (contactAsked && meaningful.every(_contactFiller.contains)) {
      return const ContactIntent();
    }

    // 12. thanks / bye
    final thanksAsked =
        tokens.any(_thanksWords.contains) ||
        tokens.any(_byeWords.contains) ||
        _hasPhrase(tokens, 'see you') ||
        _hasPhrase(tokens, 'good night');
    if (thanksAsked && meaningful.every(_thanksFiller.contains)) {
      return ThanksIntent(
        farewell:
            tokens.any(_byeWords.contains) ||
            _hasPhrase(tokens, 'see you') ||
            _hasPhrase(tokens, 'good night'),
      );
    }

    // 13. help / greeting
    final helpAsked =
        tokens.any(_helpWords.contains) ||
        _helpPhrases.any((p) => _hasPhrase(tokens, p));
    if ((helpAsked || tokens.any(_greetWords.contains)) &&
        meaningful.every(_helpFiller.contains)) {
      return HelpIntent(greeting: !helpAsked);
    }

    // 14. brands
    if (tokens.any(_brandWords.contains) &&
        meaningful.every(_brandFiller.contains)) {
      return const BrandsIntent();
    }

    // 15. cheapest / budget
    final cheapest = _parseCheapest(text, tokens);
    if (cheapest != null) return cheapest;

    // 16. price
    if (_hasPhrase(tokens, 'how much') || tokens.any(_priceWords.contains)) {
      return PriceIntent(_query(meaningful, _priceFiller));
    }

    // 17. stock
    if (tokens.any(_stockWords.contains) || _hasPhrase(tokens, 'sold out')) {
      return StockIntent(_query(meaningful, _stockFiller));
    }

    // 18. recipe ideas
    final recipe = _parseRecipe(tokens, meaningful);
    if (recipe != null) return recipe;

    // 19. all categories
    if ((tokens.any(_allCategoriesWords.contains) ||
            _allCategoriesPhrases.any((p) => _hasPhrase(tokens, p))) &&
        meaningful.every(_allCategoriesFiller.contains)) {
      return const AllCategoriesIntent();
    }

    // 20. a collection or a category, when nothing else is named
    final shortcut = _collectionOrCategory(meaningful);
    if (shortcut != null) return shortcut;

    // 21. product search ("zespri brand" searches for "zespri")
    final query = meaningful.where((w) => !_brandWords.contains(w)).toList();
    return SearchIntent((query.isEmpty ? meaningful : query).join(' '));
  }

  /// Index of the word that makes [tokens] an add command, or -1: `add`
  /// anywhere, `buy` / `order` only at the start (after "please", "can
  /// you"), and `put` / `get` only when a cart is named after it.
  static int _addTrigger(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final word = tokens[i];
      if (word == 'add') return i;
      if (word == 'buy' && tokens.take(i).every(_polite.contains)) return i;
      if (word == 'order' &&
          tokens.take(i).every(_polite.contains) &&
          !tokens.any(_orderQuestion.contains)) {
        return i;
      }
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
    final tokens = _cartTokens(words(lower.replaceAll(_measure, ' ')));
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
        final secondItem =
            int.tryParse(word) != null ||
            (word == 'and' &&
                next != null &&
                (_quantity(next) != null ||
                    const {'a', 'an', 'some'}.contains(next)));
        // Another request: "... and show me offers", "... and checkout".
        final otherRequest =
            word == 'and' &&
            rest
                .skip(i + 1)
                .any(
                  (w) =>
                      _offerWords.contains(w) ||
                      _cartWords.contains(w) ||
                      _checkoutWords.contains(w) ||
                      w == 'check',
                );
        if (secondItem || otherRequest) {
          moreItems = true;
          break;
        }
      }
      if (stopWords.contains(word) ||
          _addFiller.contains(word) ||
          _offerWords.contains(word)) {
        continue;
      }
      product.add(word);
    }
    return AddIntent(
      quantity: quantity,
      query: product.join(' '),
      measureAsked: measure,
      moreItems: moreItems,
    );
  }

  /// Left out of a "remove" message on top of [stopWords].
  static const Set<String> _removeFiller = {
    ..._removeWords,
    'take',
    'out',
    'from',
    'off',
    'rid',
    'cart',
    'bag',
    'trolley',
    'all',
    'item',
    'items',
    'them',
    'those',
    'these',
    'unit',
    'units',
    'pack',
    'packs',
    'x',
  };

  static RemoveIntent _parseRemove(String text) {
    // "the 1 kg strawberries" names a size, not a number of units.
    final tokens = _cartTokens(
      words(text.toLowerCase().replaceAll(_measure, ' ')),
    );
    int? quantity;
    final product = <String>[];
    for (final word in tokens) {
      if (_unitWords.contains(word) || _fractionWords.contains(word)) continue;
      if (product.isEmpty && quantity == null) {
        final number =
            _quantity(word) ?? (word == 'a' || word == 'an' ? 1 : null);
        if (number != null) {
          quantity = number < 1 ? 1 : number;
          continue;
        }
      }
      if (stopWords.contains(word) || _removeFiller.contains(word)) continue;
      if (_negations.contains(word)) continue;
      product.add(word);
    }
    return RemoveIntent(query: product.join(' '), quantity: quantity);
  }

  static bool _isContact(List<String> tokens) {
    if (tokens.any(_contactWords.contains)) return true;
    if (_contactPhrases.any((p) => _hasPhrase(tokens, p))) return true;
    if (tokens.contains('track') && tokens.contains('order')) return true;
    // "Where is my order?", "order status", "when will my parcel come?"
    final asksWhere = tokens.any(const {'where', 'status', 'when'}.contains);
    if (asksWhere &&
        tokens.any(const {'order', 'orders', 'parcel', 'package'}.contains)) {
      return true;
    }
    if (tokens.contains('delivery') &&
        (tokens.contains('status') ||
            (tokens.contains('where') && tokens.contains('my')))) {
      return true;
    }
    if (tokens.any(_issueWords.contains) && tokens.any(_orderWords.contains)) {
      return true;
    }
    return tokens.any(_notYet.contains) && tokens.any(_arrived.contains);
  }

  /// Words that make "express" a question about the service, not a
  /// request for the Express products.
  static const Set<String> _expressStatusWords = {
    'open',
    'opens',
    'opening',
    'close',
    'closes',
    'closed',
    'closing',
    'available',
    'availability',
    'area',
    'zone',
    'hours',
    'time',
    'times',
    'now',
    'today',
    'tonight',
    'running',
    'cover',
    'covers',
    'reach',
    'eta',
    'long',
    'until',
    'till',
  };
  static const Set<String> _expressQuestionStarts = {
    'is',
    'are',
    'can',
    'could',
    'do',
    'does',
    'will',
    'when',
    'how',
  };

  static bool _asksExpress(List<String> tokens) {
    final named =
        tokens.contains('express') ||
        tokens.contains('1hr') ||
        const [
          '1 hour',
          'one hour',
          '1 hr',
          'an hour',
          '60 min',
          '60 mins',
          '60 minutes',
        ].any((p) => _hasPhrase(tokens, p));
    if (!named) return false;
    return tokens.any(_deliveryWords.contains) ||
        tokens.any(_expressStatusWords.contains) ||
        (tokens.isNotEmpty && _expressQuestionStarts.contains(tokens.first));
  }

  static bool _isPayment(List<String> tokens) {
    if (tokens.any(_paymentWords.contains)) return true;
    if (tokens.any(_cardWords.contains) &&
        !tokens.any(_greetingCard.contains)) {
      return true;
    }
    for (final wallet in const ['apple pay', 'google pay', 'samsung pay']) {
      if (_hasPhrase(tokens, wallet)) return true;
    }
    final payAt = tokens.indexWhere((w) => w == 'pay' || w == 'paying');
    if (payAt < 0) return false;
    if (tokens.any(_payHow.contains)) return true;
    // "How can I pay?", not "How much do I have to pay?".
    final howAt = tokens.indexOf('how');
    return howAt >= 0 && howAt < payAt && !tokens.contains('much');
  }

  static CheapestIntent? _parseCheapest(String text, List<String> tokens) {
    final lower = text.toLowerCase();
    final limit = _priceLimit.firstMatch(lower);
    final asked =
        limit != null ||
        tokens.any(_cheapWords.contains) ||
        _cheapPhrases.any((p) => _hasPhrase(tokens, p));
    if (!asked) return null;

    int? maxCents;
    var rest = lower;
    if (limit != null) {
      final amount = (limit.group(1) ?? limit.group(2))!.replaceAll(',', '.');
      maxCents = (double.parse(amount) * 100).round();
      rest = lower.replaceRange(limit.start, limit.end, ' ');
    }
    final query = words(rest)
        .where(
          (w) =>
              !stopWords.contains(w) &&
              !_commandFiller.contains(w) &&
              !_cheapFiller.contains(w) &&
              !_unitWords.contains(w) &&
              int.tryParse(w) == null,
        )
        .join(' ');
    return CheapestIntent(query, maxPriceCents: maxCents);
  }

  static AssistantIntent? _parseRecipe(
    List<String> tokens,
    List<String> meaningful,
  ) {
    final found = _findRecipe(tokens);
    if (found != null) {
      final (recipe, at) = found;
      var before = at - 1;
      while (before >= 0 && _determiners.contains(tokens[before])) {
        before--;
      }
      final forDish = before >= 0 && tokens[before] == 'for';
      if (forDish || tokens.any(_dishTriggers.contains)) {
        return RecipeIntent(recipe);
      }
      return null;
    }

    final ideasAsked = tokens.any(_ideasTriggers.contains);
    if (!ideasAsked) return null;

    // "What can I make with avocado?" -> the first dish that uses it.
    final withAt = tokens.indexWhere((w) => w == 'with' || w == 'using');
    if (withAt >= 0) {
      for (final word in tokens.skip(withAt + 1)) {
        final ingredient = singular(word);
        for (final recipe in recipes) {
          if (recipe.ingredients.contains(ingredient)) {
            return RecipeIntent(recipe);
          }
        }
      }
    }

    if (meaningful.every(_ideasFiller.contains)) {
      return const RecipeIdeasIntent();
    }
    return null;
  }

  /// The first dish named in [tokens] and the index of its first word;
  /// at one position the longest name wins ("fruit salad" over "salad").
  static (Recipe, int)? _findRecipe(List<String> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      Recipe? best;
      var bestLength = 0;
      for (final recipe in recipes) {
        for (final alias in recipe.aliases) {
          final parts = alias.split(' ');
          if (parts.length > bestLength && _matchesAt(tokens, i, parts)) {
            best = recipe;
            bestLength = parts.length;
          }
        }
      }
      if (best != null) return (best, i);
    }
    return null;
  }

  /// [CollectionIntent] or [CategoryIntent] when every word of
  /// [meaningful] (filler aside) names a collection or a category;
  /// otherwise null. A two-word name beats a collection word, which
  /// beats a category word ("fruit platter" is Fruit Platters).
  static AssistantIntent? _collectionOrCategory(List<String> meaningful) {
    final named = meaningful
        .where(
          (w) => !_categoryFiller.contains(w) && !_collectionFiller.contains(w),
        )
        .toList();
    if (named.isEmpty) return null;

    String? phrase;
    CollectionShortcut? collection;
    String? category;
    var i = 0;
    while (i < named.length) {
      final pair = i + 1 < named.length ? '${named[i]} ${named[i + 1]}' : null;
      final phraseHandle = pair == null ? null : _collectionPhrases[pair];
      if (phraseHandle != null) {
        phrase ??= phraseHandle;
        i += 2;
        continue;
      }
      final word = named[i];
      final shortcut = collectionAliases[word];
      final categoryHandle = categoryAliases[word];
      if (shortcut != null) {
        collection ??= shortcut;
      } else if (categoryHandle != null) {
        category ??= categoryHandle;
      } else {
        return null;
      }
      i++;
    }
    final handle = phrase ?? collection?.handle ?? category!;
    for (final entry in Catalog.categories) {
      if (entry.handle == handle) return CategoryIntent(entry);
    }
    return CollectionIntent(collections.firstWhere((c) => c.handle == handle));
  }

  /// [meaningful] without [filler], numbers and units, as one search
  /// query ("how much is 1 kg avocado" -> "avocado").
  static String _query(List<String> meaningful, Set<String> filler) =>
      meaningful
          .where(
            (w) =>
                !filler.contains(w) &&
                !_unitWords.contains(w) &&
                int.tryParse(w) == null,
          )
          .join(' ');

  /// True when the words of [phrase] appear one after another in
  /// [tokens].
  static bool _hasPhrase(List<String> tokens, String phrase) {
    final parts = phrase.split(' ');
    for (var i = 0; i + parts.length <= tokens.length; i++) {
      if (_matchesAt(tokens, i, parts)) return true;
    }
    return false;
  }

  static bool _matchesAt(List<String> tokens, int at, List<String> parts) {
    if (at + parts.length > tokens.length) return false;
    for (var j = 0; j < parts.length; j++) {
      if (tokens[at + j] != parts[j]) return false;
    }
    return true;
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
