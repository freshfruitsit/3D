import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/assistant/assistant_brain.dart';
import 'package:fresh_market_app/assistant/assistant_intent.dart';

AssistantIntent parse(String text) => AssistantIntentParser.parse(text);

void expectAdd(String text, int quantity, String query) {
  final intent = parse(text);
  expect(intent, isA<AddIntent>(), reason: text);
  intent as AddIntent;
  expect(intent.quantity, quantity, reason: text);
  expect(intent.query, query, reason: text);
}

void expectCategory(String text, String handle) {
  final intent = parse(text);
  expect(intent, isA<CategoryIntent>(), reason: text);
  expect((intent as CategoryIntent).category.handle, handle, reason: text);
}

void expectSearch(String text, String query) {
  final intent = parse(text);
  expect(intent, isA<SearchIntent>(), reason: text);
  expect((intent as SearchIntent).query, query, reason: text);
}

/// A short, comparable form of [intent] for the tables below.
String describe(AssistantIntent intent) => switch (intent) {
  AddIntent(:final quantity, :final query) => 'Add($quantity, $query)',
  RemoveIntent(:final quantity, :final query) =>
    'Remove(${quantity ?? 'all'}, $query)',
  ClearCartIntent() => 'ClearCart',
  CheckoutIntent() => 'Checkout',
  CartIntent() => 'Cart',
  OffersIntent() => 'Offers',
  CategoryIntent(:final category) => 'Category(${category.handle})',
  CollectionIntent(:final collection) => 'Collection(${collection.handle})',
  AllCategoriesIntent() => 'AllCategories',
  CheapestIntent(:final query, :final maxPriceCents) =>
    maxPriceCents == null
        ? 'Cheapest($query)'
        : 'Cheapest($query, $maxPriceCents)',
  PriceIntent(:final query) => 'Price($query)',
  StockIntent(:final query) => 'Stock($query)',
  RecipeIntent(:final recipe) => 'Recipe(${recipe.name})',
  RecipeIdeasIntent() => 'RecipeIdeas',
  FavouritesIntent() => 'Favourites',
  ContactIntent() => 'Contact',
  PaymentIntent() => 'Payment',
  DeliveryIntent() => 'Delivery',
  ExpressIntent() => 'Express',
  BrandsIntent() => 'Brands',
  HelpIntent(:final greeting) => greeting ? 'Greeting' : 'Help',
  ThanksIntent(:final farewell) => farewell ? 'Bye' : 'Thanks',
  SearchIntent(:final query) => 'Search($query)',
};

void expectTable(List<(String, String)> table) {
  for (final (text, expected) in table) {
    expect(describe(parse(text)), expected, reason: text);
  }
}

void main() {
  test('words are lower-cased and punctuation is dropped', () {
    expect(AssistantIntentParser.words("  What's ON offer?! "), [
      'whats',
      'on',
      'offer',
    ]);
    expect(AssistantIntentParser.words('Add 2, cucumbers.'), [
      'add',
      '2',
      'cucumbers',
    ]);
    expect(AssistantIntentParser.words('...'), isEmpty);
  });

  group('add', () {
    test('quantity as digits, as a word, or 1 by default', () {
      expectAdd('Add 2 cucumbers', 2, 'cucumbers');
      expectAdd('add three kiwi', 3, 'kiwi');
      expectAdd('Buy strawberry', 1, 'strawberry');
      expectAdd('add ten Blueberry', 10, 'blueberry');
    });

    test('quantity is capped at 20 and never below 1', () {
      expectAdd('add 500 lemons', 20, 'lemons');
      expectAdd('add 0 lemons', 1, 'lemons');
    });

    test('filler words around the product are dropped', () {
      expectAdd('Please add 2 cucumbers to my cart!', 2, 'cucumbers');
      expectAdd('Please buy some beef cubes', 1, 'beef cubes');
      expectAdd('I want to add 2 kiwi', 2, 'kiwi');
      expectAdd('can you add a kiwi to the basket', 1, 'kiwi');
    });

    test('only the first number is the quantity', () {
      expectAdd('add 2 seven up', 2, 'seven up');
    });

    test('no product named', () {
      expectAdd('add', 1, '');
      expectAdd('add to cart', 1, '');
    });

    test('wins over every later rule', () {
      expectAdd('add berries to cart', 1, 'berries');
      expectAdd('add 2 checkout bags', 2, 'checkout bags');
    });

    test('only a command adds: questions, negations and a "buy" inside '
        'a sentence are searches', () {
      expectSearch('Where can I buy strawberries?', 'strawberries');
      expectSearch("Don't add onions", 'onions');
      expectSearch('do not add onions', 'onions');
      expectSearch('I want to buy some apples', 'apples');
      expectSearch('How do I add a kiwi?', 'kiwi');
      expectCategory('Where can I buy berries?', 'berries');
    });

    test('an offer word wins over buy / add', () {
      for (final text in ['Buy 1 get 1 free offers', 'buy 2 deals']) {
        expect(parse(text), isA<OffersIntent>(), reason: text);
      }
    });

    test('a second item is left out and flagged', () {
      var intent = parse('Add 2 apples and 3 bananas') as AddIntent;
      expect(intent.quantity, 2);
      expect(intent.query, 'apples');
      expect(intent.moreItems, isTrue);

      intent = parse('add 2 apples, 3 bananas') as AddIntent;
      expect(intent.query, 'apples');
      expect(intent.moreItems, isTrue);

      intent = parse('add apples and some bananas') as AddIntent;
      expect(intent.query, 'apples');
      expect(intent.moreItems, isTrue);

      intent = parse('add 2 cucumbers') as AddIntent;
      expect(intent.moreItems, isFalse);
      expect(intent.measureAsked, isFalse);
    });

    test('3x, x3 and dozen are quantities', () {
      expectAdd('Add 3x bananas', 3, 'bananas');
      expectAdd('add bananas x3', 3, 'bananas');
      expectAdd('add a dozen eggs', 12, 'eggs');
    });

    test('a weight is never turned into a unit count', () {
      for (final (text, query) in [
        ('add 1.5 kg potatoes', 'potatoes'),
        ('add 2kg tomatoes', 'tomatoes'),
        ('Add half a kilo of tomatoes', 'tomatoes'),
        ('add 500 g cherries', 'cherries'),
      ]) {
        final intent = parse(text);
        expect(intent, isA<AddIntent>(), reason: text);
        intent as AddIntent;
        expect(intent.measureAsked, isTrue, reason: text);
        expect(intent.quantity, 1, reason: text);
        expect(intent.query, query, reason: text);
      }
    });

    test('put ... in my cart adds', () {
      expectAdd('Put 2 cucumbers in my cart', 2, 'cucumbers');
      expectAdd('get me a kiwi in my basket', 1, 'kiwi');
    });
  });

  // Was one RemoveIntent the assistant refused; now remove names the
  // product and emptying the cart is its own (confirmed) intent.
  test('remove names what to remove; empty is its own intent', () {
    for (final (text, query) in [
      ('Remove cucumbers from my cart', 'cucumbers'),
      ('delete kiwi', 'kiwi'),
      ('take the kiwi out of my cart', 'kiwi'),
    ]) {
      final intent = parse(text);
      expect(intent, isA<RemoveIntent>(), reason: text);
      expect((intent as RemoveIntent).query, query, reason: text);
      expect(intent.quantity, isNull, reason: text);
    }
    for (final text in ['Empty my cart', 'clear the basket']) {
      expect(parse(text), isA<ClearCartIntent>(), reason: text);
    }
  });

  group('rule order', () {
    test('checkout before cart', () {
      expect(parse('checkout my cart'), isA<CheckoutIntent>());
    });
  });

  test('checkout', () {
    for (final text in ['Checkout', 'I want to pay', 'check out', 'Pay now']) {
      expect(parse(text), isA<CheckoutIntent>(), reason: text);
    }
    // Before cart.
    expect(parse('checkout my cart'), isA<CheckoutIntent>());
  });

  test('cart', () {
    for (final text in ['Open my cart', "what's in my basket?", 'CART']) {
      expect(parse(text), isA<CartIntent>(), reason: text);
    }
  });

  test('offers', () {
    for (final text in [
      'What is on offer?',
      'offers',
      'any deals today',
      'Best deal',
      'what is on sale',
      'discount',
      'show me discounts',
    ]) {
      expect(parse(text), isA<OffersIntent>(), reason: text);
    }
    // Before categories.
    expect(parse('meat offers'), isA<OffersIntent>());
  });

  group('category', () {
    test('every catalogue tile and alias', () {
      const cases = {
        'fruit': 'fruits',
        'Fruits': 'fruits',
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
      cases.forEach(expectCategory);
    });

    test('inside a sentence', () {
      expectCategory('Show me berries', 'berries');
      expectCategory('Do you have any flowers?', 'ambrosia-flowers');
      expectCategory('open the fresh meat section', 'fresh-meat');
      expectCategory('exotic fruits', 'tropical-exotic');
    });

    test('a category word next to other product words is a search', () {
      expectSearch('orange juice', 'orange juice');
      expectSearch('strawberries', 'strawberries');
    });
  });

  group('search', () {
    test('stop words are removed', () {
      expectSearch('Find avocado', 'avocado');
      expectSearch('Do you have any Zespri kiwi, please?', 'zespri kiwi');
      expectSearch('I need some lamb chops', 'lamb chops');
    });

    // "Hi!" was an empty search; it is a greeting now.
    test('nothing left to search for', () {
      expectSearch('', '');
      expectSearch('please', '');
      expectSearch('show me', '');
    });
  });

  test('singular', () {
    expect(AssistantIntentParser.singular('cucumbers'), 'cucumber');
    expect(AssistantIntentParser.singular('berries'), 'berry');
    expect(AssistantIntentParser.singular('mangoes'), 'mango');
    expect(AssistantIntentParser.singular('lamb chops'), 'lamb chop');
    expect(AssistantIntentParser.singular('kiwi'), 'kiwi');
    expect(AssistantIntentParser.singular('citrus'), 'citrus');
    expect(AssistantIntentParser.singular('watercress'), 'watercress');
  });

  group('shopper phrases', () {
    test('help and greetings', () {
      expectTable([
        ('hi', 'Greeting'),
        ('Hello there!', 'Greeting'),
        ('hey', 'Greeting'),
        ('Good morning', 'Greeting'),
        ('help', 'Help'),
        ('I need help', 'Help'),
        ('What can you do?', 'Help'),
        ('options', 'Help'),
        ('Show me the menu', 'Help'),
        ('how does this work', 'Help'),
        // Something else named: that wins.
        ('hi, show me berries', 'Category(berries)'),
        ('help me find avocado', 'Search(avocado)'),
      ]);
    });

    test('thanks and bye', () {
      expectTable([
        ('thanks', 'Thanks'),
        ('Thank you so much!', 'Thanks'),
        ('thanks for the help', 'Thanks'),
        ('no thanks', 'Thanks'),
        ('bye', 'Bye'),
        ('ok bye, see you later', 'Bye'),
        ('thanks, add 2 cucumbers', 'Add(2, cucumbers)'),
      ]);
    });

    test('all categories', () {
      expectTable([
        ('categories', 'AllCategories'),
        ('Show all categories', 'AllCategories'),
        ('What do you sell?', 'AllCategories'),
        ('browse', 'AllCategories'),
        ('departments', 'AllCategories'),
        ('what do you have', 'AllCategories'),
        // A category named is that category.
        ('fruit categories', 'Category(fruits)'),
        ('browse fruits', 'Category(fruits)'),
      ]);
    });

    test('collection shortcuts', () {
      expectTable([
        ('Show local UAE produce', 'Collection(local-uae)'),
        ('anything made in UAE', 'Collection(local-uae)'),
        ('emirati products', 'Collection(local-uae)'),
        ('organic food', 'Collection(organic-food)'),
        ("What's new?", 'Collection(new-arrivals)'),
        ('new arrivals', 'Collection(new-arrivals)'),
        ('latest products', 'Collection(new-arrivals)'),
        ('What is popular?', 'Collection(best-sellers)'),
        ('best sellers', 'Collection(best-sellers)'),
        ('bestsellers', 'Collection(best-sellers)'),
        ('what do you recommend', 'Collection(best-sellers)'),
        ('top', 'Collection(best-sellers)'),
        ('trending', 'Collection(trending)'),
        ('1hr express products', 'Collection(express)'),
        ('one hour', 'Collection(express)'),
        ('1 hour', 'Collection(express)'),
        ('I need it urgent', 'Collection(express)'),
        ('bulk', 'Collection(bulk-buy)'),
        ('buy in bulk', 'Collection(bulk-buy)'),
        ('wholesale', 'Collection(bulk-buy)'),
        ('milk', 'Collection(dairy)'),
        ('dairy products', 'Collection(dairy)'),
        ('eggs', 'Collection(eggs-cheese)'),
        ('cheese', 'Collection(eggs-cheese)'),
        ('dates', 'Collection(dates)'),
        ('nuts', 'Collection(nuts-dried-fruits)'),
        ('dried fruits', 'Collection(nuts-dried-fruits)'),
        ('healthy snacks', 'Collection(healthy-pouches)'),
        ('pouches', 'Collection(healthy-pouches)'),
        ('fruit platter', 'Collection(ambrosia-platters)'),
        ('party platters', 'Collection(ambrosia-platters)'),
        ('fruit bouquet', 'Collection(ambrosia-bouquets)'),
        ('birthday gift', 'Collection(ambrosia-occasions)'),
        ('anniversary', 'Collection(ambrosia-occasions)'),
        ('wedding flowers', 'Collection(ambrosia-occasions)'),
        ('celebration', 'Collection(ambrosia-occasions)'),
        ('Eid gifts', 'Collection(ambrosia-eid)'),
        ('ramadan', 'Collection(ambrosia-ramadan)'),
        ('iftar', 'Collection(ambrosia-ramadan)'),
        ('christmas hamper', 'Collection(ambrosia-christmas)'),
        ("Valentine's Day", 'Collection(ambrosia-valentines)'),
        ("mother's day", 'Collection(ambrosia-mothers-day)'),
        ('something for my mum', 'Collection(ambrosia-mothers-day)'),
        ("women's day", 'Collection(ambrosia-mothers-day)'),
        // A flower bouquet is Flowers, not Fruit Bouquets.
        ('flower bouquet', 'Category(ambrosia-flowers)'),
        // Gifts stay the Hampers category (the brain adds gift buttons).
        ('Gift ideas', 'Category(hampers)'),
        ('gifts', 'Category(hampers)'),
        // Other product words make it a search.
        ('new zealand kiwi', 'Search(new zealand kiwi)'),
        ('low fat milk', 'Search(low fat milk)'),
        ('milk chocolate', 'Search(milk chocolate)'),
        // A product, not a collection, after "add".
        ('add dates', 'Add(1, dates)'),
      ]);
    });

    test('every collection shortcut is reachable', () {
      final reached = {
        for (final shortcut in AssistantIntentParser.collections)
          shortcut.handle: AssistantIntentParser.collectionAliases.values.any(
            (c) => c.handle == shortcut.handle,
          ),
      };
      expect(reached.values, everyElement(isTrue));
      expect({
        for (final c in AssistantIntentParser.collections) c.handle,
      }, hasLength(AssistantIntentParser.collections.length));
    });

    test('cheapest and budget', () {
      expectTable([
        ('Cheapest avocado', 'Cheapest(avocado)'),
        ('cheap berries', 'Cheapest(berries)'),
        ('avocado under 20', 'Cheapest(avocado, 2000)'),
        ('strawberries below 30 dhs', 'Cheapest(strawberries, 3000)'),
        ('kiwi less than 15 aed', 'Cheapest(kiwi, 1500)'),
        ('budget mango', 'Cheapest(mango)'),
        ('blueberries under AED 12.50', 'Cheapest(blueberries, 1250)'),
        ('lettuce for 10 dhs or less', 'Cheapest(lettuce, 1000)'),
        ('the least expensive dates', 'Cheapest(dates)'),
        ('cheapest', 'Cheapest()'),
        ('something under 20', 'Cheapest(, 2000)'),
        // An offer word still means offers.
        ('cheap deals', 'Offers'),
      ]);
    });

    test('price', () {
      expectTable([
        ('How much is avocado?', 'Price(avocado)'),
        ('price of kiwi', 'Price(kiwi)'),
        ('What does a cucumber cost?', 'Price(cucumber)'),
        ('how much are the strawberries', 'Price(strawberries)'),
        ('avocado price', 'Price(avocado)'),
        ('how much is 1 kg avocado', 'Price(avocado)'),
        ('how much', 'Price()'),
        // Earlier rules.
        ('how much is my cart', 'Cart'),
        ('how much is delivery', 'Delivery'),
      ]);
    });

    test('stock', () {
      expectTable([
        ('Is avocado available?', 'Stock(avocado)'),
        ('do you have kiwi in stock', 'Stock(kiwi)'),
        ('blueberry in stock?', 'Stock(blueberry)'),
        ('are the blueberries sold out', 'Stock(blueberries)'),
        ('When will raspberries be back in stock?', 'Stock(raspberries)'),
        // Without a stock word "do you have" stays a search.
        ('do you have kiwi', 'Search(kiwi)'),
      ]);
    });

    test('recipe ideas', () {
      expectTable([
        ('Ideas for a fruit salad', 'Recipe(fruit salad)'),
        ('smoothie recipe', 'Recipe(smoothie)'),
        ('salad ideas', 'Recipe(green salad)'),
        ('green salad recipe', 'Recipe(green salad)'),
        ('how to make guacamole', 'Recipe(guacamole)'),
        ('something for a BBQ', 'Recipe(BBQ)'),
        ('what can I cook on the grill', 'Recipe(BBQ)'),
        ('What can I make for breakfast?', 'Recipe(breakfast)'),
        ('what can I make with avocado', 'Recipe(guacamole)'),
        ('add everything for a smoothie', 'Recipe(smoothie)'),
        ('recipe ideas', 'RecipeIdeas'),
        ('ideas', 'RecipeIdeas'),
        ('what should I cook tonight', 'RecipeIdeas'),
        // Without a recipe word a dish stays what it was.
        ('salad', 'Category(lettuce-greens)'),
        ('cooking oil', 'Search(cooking oil)'),
        ('ideas for a party', 'Collection(ambrosia-occasions)'),
      ]);
    });

    test('every recipe message asks for that recipe', () {
      for (final recipe in AssistantIntentParser.recipes) {
        expect(
          describe(parse(recipe.message)),
          'Recipe(${recipe.name})',
          reason: recipe.message,
        );
        expect(
          recipe.ingredients.length,
          lessThanOrEqualTo(AssistantBrain.maxRecipeProducts),
        );
      }
      expect(AssistantIntentParser.recipes.map((r) => r.message), [
        'Ideas for a fruit salad',
        'Ideas for a smoothie',
        'Ideas for a green salad',
        'Ideas for guacamole',
        'Ideas for a BBQ',
        'Ideas for breakfast',
      ]);
      expect(AssistantIntentParser.recipes.first.label, 'Fruit salad ideas');
    });

    test('remove', () {
      expectTable([
        ('remove cucumbers', 'Remove(all, cucumbers)'),
        ('remove 1 cucumber', 'Remove(1, cucumber)'),
        ('Delete the bananas from my cart', 'Remove(all, bananas)'),
        ('take the berries out of my cart', 'Remove(all, berries)'),
        ('remove two kiwis', 'Remove(2, kiwis)'),
        ('remove a kiwi', 'Remove(1, kiwi)'),
        ('get rid of the onions', 'Remove(all, onions)'),
        ('remove the 1 kg strawberries', 'Remove(all, strawberries)'),
        ('remove all cucumbers', 'Remove(all, cucumbers)'),
        ('Remove clear honey', 'Remove(all, clear honey)'),
        ('remove', 'Remove(all, )'),
        // Favourites are not the cart.
        ('remove kiwi from my favourites', 'Favourites'),
      ]);
    });

    test('empty the cart', () {
      expectTable([
        ('empty my cart', 'ClearCart'),
        ('Clear my cart', 'ClearCart'),
        ('remove everything', 'ClearCart'),
        ('delete all items from my basket', 'ClearCart'),
        ('take everything out of my cart', 'ClearCart'),
        ('please empty the basket', 'ClearCart'),
        // A question is not a command.
        ('is my cart empty?', 'Cart'),
      ]);
    });

    test('favourites', () {
      expectTable([
        ('my favourites', 'Favourites'),
        ('show my favorites', 'Favourites'),
        ('saved items', 'Favourites'),
        ('wishlist', 'Favourites'),
        ('my wish list', 'Favourites'),
        ('my list', 'Favourites'),
        ('add kiwi to my favourites', 'Favourites'),
      ]);
    });

    test('contact', () {
      expectTable([
        ('Contact customer service', 'Contact'),
        ('what is your phone number', 'Contact'),
        ('can I call you', 'Contact'),
        ('email address', 'Contact'),
        ('customer care', 'Contact'),
        ('I have a complaint', 'Contact'),
        ('support', 'Contact'),
        ('opening hours', 'Contact'),
        ('where are you located', 'Contact'),
        ('store address', 'Contact'),
        ('when do you open', 'Contact'),
        ('my order is late', 'Contact'),
        ('track my order', 'Contact'),
        ("my order hasn't arrived", 'Contact'),
        ('order status', 'Contact'),
        // Not about the store.
        ('where do you have berries', 'Category(berries)'),
      ]);
    });

    test('payment', () {
      expectTable([
        ('payment methods', 'Payment'),
        ('How can I pay?', 'Payment'),
        ('cash on delivery', 'Payment'),
        ('do you take apple pay', 'Payment'),
        ('card', 'Payment'),
        ('pay by card', 'Payment'),
        ('do you accept credit cards', 'Payment'),
        // Paying now is still checkout.
        ('pay', 'Checkout'),
        ('pay now', 'Checkout'),
        ('how much do I have to pay', 'Checkout'),
        // A greeting card is not a payment card.
        ('gift card', 'Search(gift card)'),
      ]);
    });

    test('delivery', () {
      expectTable([
        ('delivery', 'Delivery'),
        ('do you deliver to Abu Dhabi?', 'Delivery'),
        ('shipping', 'Delivery'),
        ('when will it arrive', 'Delivery'),
        ('delivery fee', 'Delivery'),
        ('delivery time', 'Delivery'),
        ('Delivery information', 'Delivery'),
        ('express delivery', 'Express'),
        ('change my address', 'Delivery'),
      ]);
    });

    test('questions about Express ask for its status', () {
      expectTable([
        ('Is Express open?', 'Express'),
        ('is express available in my area', 'Express'),
        ('can I get it in 1 hour', 'Express'),
        ('Do you deliver in one hour?', 'Express'),
        ('1 hour delivery', 'Express'),
        ('what time does express close', 'Express'),
        // Naming Express alone still opens its products.
        ('express', 'Collection(express)'),
        ('Show 1Hr Express', 'Collection(express)'),
        ('1 hour', 'Collection(express)'),
        // Delivery without Express stays a delivery question.
        ('how fast is delivery', 'Delivery'),
      ]);
    });

    test('brands', () {
      expectTable([
        ('brands', 'Brands'),
        ('brands you have', 'Brands'),
        ('which brands do you stock', 'Brands'),
        // One brand is a product search.
        ('Zespri', 'Search(zespri)'),
        ('zespri brand', 'Search(zespri)'),
        ('Find Zespri', 'Search(zespri)'),
      ]);
    });

    test('order at the start is a command', () {
      expectTable([
        ('order 2 cucumbers', 'Add(2, cucumbers)'),
        ('please order a kiwi', 'Add(1, kiwi)'),
      ]);
    });
  });

  group('ready-made messages', () {
    test('every default suggestion parses to what it says', () {
      const expected = [
        'Offers',
        'Category(berries)',
        'Add(2, cucumbers)',
        'Recipe(fruit salad)',
        'Cheapest(avocado)',
        'Collection(local-uae)',
        'Category(hampers)',
        'Collection(new-arrivals)',
        'Contact',
        'Cart',
      ];
      expect([
        for (final s in AssistantBrain.defaultSuggestions) describe(parse(s)),
      ], expected);
    });

    test('every quick option parses to what its card shows', () {
      final expected = {
        QuickOptionKind.offers: 'Offers',
        QuickOptionKind.categories: 'AllCategories',
        QuickOptionKind.recipes: 'RecipeIdeas',
        QuickOptionKind.local: 'Collection(local-uae)',
        QuickOptionKind.gifts: 'Category(hampers)',
        QuickOptionKind.popular: 'Collection(best-sellers)',
        QuickOptionKind.cart: 'Cart',
        QuickOptionKind.contact: 'Contact',
      };
      expect(AssistantBrain.quickOptions, hasLength(8));
      for (final option in AssistantBrain.quickOptions) {
        expect(
          describe(parse(option.message)),
          expected[option.kind],
          reason: option.message,
        );
      }
    });
  });

  group('second review', () {
    test('basket is the cart only when no product word comes before it', () {
      expectTable([
        ('basket', 'Cart'),
        ("what's in my basket?", 'Cart'),
        ('show basket', 'Cart'),
        ('can you add a kiwi to the basket', 'Add(1, kiwi)'),
        ('add a kiwi to a basket', 'Add(1, kiwi)'),
        ('please empty the basket', 'ClearCart'),
        // A basket the store sells.
        ('fruit basket', 'Search(fruit basket)'),
        ('gift basket', 'Search(gift basket)'),
        ('add a fruit basket', 'Add(1, fruit basket)'),
        ('get a fruit basket', 'Search(fruit basket)'),
        ('remove the fruit basket', 'Remove(all, fruit basket)'),
        ('take the fruit basket out of my basket', 'Remove(all, fruit basket)'),
      ]);
    });

    test('number words go up to twenty', () {
      expectAdd('add twenty limes', 20, 'limes');
      expectAdd('add fifteen kiwis', 15, 'kiwis');
      expectAdd('add eleven cucumbers', 11, 'cucumbers');
      expectTable([('remove twelve kiwis', 'Remove(12, kiwis)')]);
      // "basket" in a product name stays a product word in chips.
      expect(AssistantIntentParser.isPlainWord('basket'), isTrue);
      expectTable([
        ('Cheapest fruit basket', 'Cheapest(fruit basket)'),
        ('Is fruit basket in stock?', 'Stock(fruit basket)'),
        ('Add 1 Oriental Delights Basket', 'Add(1, oriental delights basket)'),
        ('Remove Basket Joy', 'Remove(all, basket joy)'),
      ]);
      for (final word in ['eleven', 'fifteen', 'twenty']) {
        expect(AssistantIntentParser.isPlainWord(word), isFalse, reason: word);
      }
    });

    test('an add with another request still adds, and says the rest was '
        'left out', () {
      var intent = parse('add 2 cucumbers and show me offers') as AddIntent;
      expect(intent.quantity, 2);
      expect(intent.query, 'cucumbers');
      expect(intent.moreItems, isTrue);

      intent = parse('add 2 cucumbers to my cart and checkout') as AddIntent;
      expect(intent.query, 'cucumbers');
      expect(intent.moreItems, isTrue);

      intent = parse('add gluten free bread') as AddIntent;
      expect(intent.query, 'gluten free bread');
      expect(intent.moreItems, isFalse);

      // Only offer words: the offers.
      expectTable([
        ('Buy 1 get 1 free offers', 'Offers'),
        ('buy one get one free', 'Offers'),
        ('buy 2 deals', 'Offers'),
      ]);
    });

    test('order and account questions are not product searches', () {
      expectTable([
        ('where is my order', 'Contact'),
        ('where is my order?', 'Contact'),
        ('when will my order come', 'Contact'),
        ('where is my delivery', 'Contact'),
        ('is there a minimum order', 'Delivery'),
        ('minimum spend for delivery', 'Delivery'),
        // Still about delivering, not about a placed order.
        ('when will it arrive', 'Delivery'),
        ('do you deliver to Abu Dhabi?', 'Delivery'),
      ]);
    });

    test('Gulf courtesy words and "sell" are not searched for', () {
      expectTable([
        ('shukran habibi', 'Thanks'),
        ('yalla bye', 'Bye'),
        ('khalas thanks', 'Bye'),
        ('salam', 'Greeting'),
        ('habibi show me mangoes', 'Category(mangoes)'),
        ('salam, do you have dates?', 'Collection(dates)'),
        ('wallah the cheapest avocado', 'Cheapest(avocado)'),
        ('do you sell chiquita bananas', 'Search(chiquita bananas)'),
        ('pls add 2 kiwis', 'Add(2, kiwis)'),
        ('what do you sell', 'AllCategories'),
      ]);
    });

    test('a typed answer to "Are you sure?"', () {
      for (final text in [
        'yes',
        'Yes please',
        'yes empty it',
        'ok, clear my cart',
        'confirm',
        'go ahead',
        'do it',
        'sure',
      ]) {
        expect(AssistantIntentParser.confirmation(text), isTrue, reason: text);
      }
      for (final text in ['no', 'No thanks', 'cancel', 'keep it', "don't"]) {
        expect(AssistantIntentParser.confirmation(text), isFalse, reason: text);
      }
      for (final text in ['', 'add 2 kiwis', 'no, add 2 kiwis', 'show me']) {
        expect(AssistantIntentParser.confirmation(text), isNull, reason: text);
      }
    });
  });

  test('plain words', () {
    for (final word in ['kiwi', 'zespri', 'sungold', 'cucumber', 'honey']) {
      expect(AssistantIntentParser.isPlainWord(word), isTrue, reason: word);
    }
    for (final word in [
      '',
      '500gm',
      '7',
      'kg',
      'offer',
      'free',
      'and',
      'clear',
      'remove',
      'cart',
      'card',
      'delivery',
      'favourite',
      'price',
      'stock',
      'the',
    ]) {
      expect(AssistantIntentParser.isPlainWord(word), isFalse, reason: word);
    }
  });
}
