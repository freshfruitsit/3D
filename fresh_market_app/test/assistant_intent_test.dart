import 'package:flutter_test/flutter_test.dart';
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

void main() {
  test('words are lower-cased and punctuation is dropped', () {
    expect(AssistantIntentParser.words("  What's ON offer?! "),
        ['whats', 'on', 'offer']);
    expect(AssistantIntentParser.words('Add 2, cucumbers.'),
        ['add', '2', 'cucumbers']);
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

  test('remove / empty is its own intent', () {
    for (final text in [
      'Remove cucumbers from my cart',
      'Empty my cart',
      'clear the basket',
      'delete kiwi',
      'take the kiwi out of my cart',
    ]) {
      expect(parse(text), isA<RemoveIntent>(), reason: text);
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

    test('nothing left to search for', () {
      expectSearch('', '');
      expectSearch('Hi!', '');
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
}
