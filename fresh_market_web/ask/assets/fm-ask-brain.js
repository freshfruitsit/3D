/*
 * Fresh Market "Ask" assistant: the scripted brain (no AI, no server).
 * A direct port of the Fresh Market app's lib/assistant/assistant_intent.dart
 * and assistant_brain.dart. Keyword rules turn a message into an intent; every
 * product and price in a reply comes from the store adapter.
 *
 *   window.FMAskBrain.create(store, config) -> brain
 *   brain.reply({text} | {option} | {chip}) -> Promise<Reply>
 *
 * It never places an order: the furthest it goes is opening /cart.
 */
(function (root) {
  'use strict';

  // ---- small helpers -------------------------------------------------------

  function set(list) {
    var s = Object.create(null);
    for (var i = 0; i < arguments.length; i++) {
      var a = arguments[i];
      for (var j = 0; j < a.length; j++) s[a[j]] = true;
    }
    return s;
  }
  function has(s, w) { return w != null && s[w] === true; }
  function inSet(s) { return function (w) { return has(s, w); }; }
  function assign(to, from) {
    for (var k in from) if (Object.prototype.hasOwnProperty.call(from, k)) to[k] = from[k];
    return to;
  }

  function any(list, f) { for (var i = 0; i < list.length; i++) if (f(list[i])) return true; return false; }
  function all(list, f) { for (var i = 0; i < list.length; i++) if (!f(list[i])) return false; return true; }
  function intOf(w) { return /^\d+$/.test(w) ? parseInt(w, 10) : null; }
  function cap(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

  // ---- word lists (assistant_intent.dart) ----------------------------------

  var MAX_ADD = 20;
  var POLITE = set(['please', 'pls', 'plz', 'can', 'could', 'would', 'you', 'kindly', 'just', 'lets']);
  var NEG = ['dont', 'not', 'never', 'wont', 'cant', 'shouldnt'];
  var NEGATIONS = set(NEG);
  var QSTART = ['where', 'how', 'what', 'whats', 'which', 'do', 'does', 'is', 'are', 'why', 'when', 'who', 'should'];
  var QUESTION_STARTS = set(QSTART);
  var REMOVE = ['remove', 'delete'];
  var REMOVE_WORDS = set(REMOVE);
  var CLEAR = ['empty', 'clear'];
  var CLEAR_WORDS = set(CLEAR);
  var CLEAR_FILLER_L = REMOVE.concat(CLEAR, ['cart', 'bag', 'trolley', 'all', 'everything', 'item', 'items', 'out', 'take',
    'whole', 'entire', 'completely', 'from', 'off', 'products']);
  var CLEAR_FILLER = set(CLEAR_FILLER_L);
  var COMMAND_FILLER = set(['add', 'buy', 'put'], NEG, QSTART);

  var UNIT_PATTERN = 'kilograms|kilogram|kilos|kilo|kgs|kg|grams|gram|gms|gm|g|ml|litres|litre|liters|liter|ltr|l|lbs|lb';
  var UNITS = UNIT_PATTERN.split('|');
  var UNIT_WORDS = set(UNITS);
  // No lookbehind (Safari < 16.4): a leading separator is matched instead.
  var MEASURE_SRC = '(?:^|[^\\p{L}\\p{N}])(?:\\d+(?:[.,]\\d+)?\\s*(?:' + UNIT_PATTERN +
    ')|\\d+[.,]\\d+)(?![\\p{L}\\p{N}])';
  function measureTest(s) { return new RegExp(MEASURE_SRC, 'u').test(s); }
  function measureStrip(s) { return s.replace(new RegExp(MEASURE_SRC, 'gu'), ' '); }
  var FRACTION_WORDS = set(['half', 'quarter']);

  var CHECKOUT = ['checkout', 'pay'];
  var CHECKOUT_WORDS = set(CHECKOUT);
  var CART_WORDS = set(['cart']);
  // "Open my cart", "go to cart", "take me to my basket": on the web this opens the cart page.
  var OPEN_CART_WORDS = set(['open', 'go', 'take', 'view']);
  var BASKET_LEAD = set(['my', 'the', 'your', 'shopping', 'to', 'in', 'into', 'from', 'of', 'open', 'show', 'view', 'see',
    'check', 'empty', 'clear', 'whole', 'entire']);
  var OFFER = ['offer', 'offers', 'deal', 'deals', 'sale', 'discount', 'discounts'];
  var OFFER_WORDS = set(OFFER);
  var ORDER_QUESTION = set(['status', 'track', 'tracking', 'history', 'number', 'cancel', 'my', 'late', 'missing', 'problem',
    'issue', 'delivered', 'arrive', 'placed', 'previous', 'last']);
  var NUMBER_WORDS = {
    one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12,
    thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19, twenty: 20
  };

  var STOP_L = ['show', 'me', 'the', 'some', 'find', 'i', 'want', 'need', 'please', 'do', 'you', 'have', 'any', 'get', 'a',
    'an', 'of', 'for', 'to', 'my', 'can', 'could', 'would', 'like', 'looking', 'look', 'search', 'is', 'are', 'there', 'what',
    'whats', 'which', 'where', 'in', 'on', 'with', 'got', 'give', 'us', 'we', 'id', 'im', 'hi', 'hello', 'hey', 'and', 'your',
    'this', 'that', 'it', 'today', 'todays', 'now', 'open', 'see', 'list', 'help', 'thanks', 'thank', 'ok', 'okay', 'yes', 'no',
    'pls', 'plz', 'habibi', 'habibti', 'yalla', 'yallah', 'wallah', 'wallahi', 'inshallah', 'mashallah', 'khalas', 'salam',
    'salaam', 'ahlan', 'sell', 'selling', 'carry'];
  var STOP = set(STOP_L);
  var ADD_FILLER = set(['cart', 'bag', 'order', 'into', 'too', 'also', 'more', 'x']);
  var CATEGORY_FILLER_L = ['fresh', 'category', 'categories', 'section', 'aisle', 'products', 'product', 'items', 'all', 'shop',
    'browse'];
  var CATEGORY_FILLER = set(CATEGORY_FILLER_L);
  var COLLECTION_FILLER = set(['produce', 'range', 'collection', 'collections', 'stuff', 'things', 'goods', 'selection',
    'from', 'idea', 'ideas', 'option', 'options', 'choices', 'food', 'foods', 'only', 'store', 'anything', 'something', 'else',
    'item', 'available']);

  var CATEGORY_ALIASES = {
    fruit: 'fruits', fruits: 'fruits', vegetable: 'vegetables', vegetables: 'vegetables', veg: 'vegetables',
    veggies: 'vegetables', meat: 'fresh-meat', butchery: 'fresh-meat', berries: 'berries', flower: 'ambrosia-flowers',
    flowers: 'ambrosia-flowers', hamper: 'hampers', hampers: 'hampers', gift: 'hampers', gifts: 'hampers', citrus: 'citrus',
    orange: 'citrus', oranges: 'citrus', lemon: 'citrus', lemons: 'citrus', mango: 'mangoes', mangoes: 'mangoes',
    mangos: 'mangoes', melon: 'melons-pineapples', melons: 'melons-pineapples', pineapple: 'melons-pineapples',
    tropical: 'tropical-exotic', exotic: 'tropical-exotic', greens: 'lettuce-greens', lettuce: 'lettuce-greens',
    salad: 'lettuce-greens', herb: 'fresh-herbs', herbs: 'fresh-herbs'
  };

  /** The category tiles (Catalog.categories): label and collection handle. */
  var CATEGORIES = [
    { label: 'Fruits', handle: 'fruits' }, { label: 'Vegetables', handle: 'vegetables' },
    { label: 'Meat', handle: 'fresh-meat' }, { label: 'Berries', handle: 'berries' },
    { label: 'Flowers', handle: 'ambrosia-flowers' }, { label: 'Hampers', handle: 'hampers' },
    { label: 'Citrus', handle: 'citrus' }, { label: 'Mangoes', handle: 'mangoes' },
    { label: 'Melons', handle: 'melons-pineapples' }, { label: 'Tropical', handle: 'tropical-exotic' },
    { label: 'Greens', handle: 'lettuce-greens' }, { label: 'Herbs', handle: 'fresh-herbs' }
  ];

  /** Store collections that are not category tiles. */
  var COLLECTIONS = [
    ['local-uae', 'Local UAE'], ['organic-food', 'Organic Food'], ['new-arrivals', 'New Arrivals'],
    ['best-sellers', 'Best Sellers'], ['trending', 'Trending This Week'], ['express', '1Hr Express'],
    ['bulk-buy', 'Bulk Buy'], ['dairy', 'Dairy'], ['eggs-cheese', 'Eggs & Cheese'], ['dates', 'Dates'],
    ['nuts-dried-fruits', 'Nuts & Dried Fruits'], ['healthy-pouches', 'Healthy Pouches'],
    ['ambrosia-platters', 'Fruit Platters'], ['ambrosia-bouquets', 'Fruit Bouquets'],
    ['ambrosia-occasions', 'Special Occasions'], ['ambrosia-eid', 'Eid'], ['ambrosia-ramadan', 'Ramadan'],
    ['ambrosia-christmas', 'Christmas'], ['ambrosia-valentines', "Valentine's Day"],
    ['ambrosia-mothers-day', "Women's & Mother's Day"]
  ].map(function (c) { return { handle: c[0], title: c[1] }; });
  function collectionBy(handle) {
    for (var i = 0; i < COLLECTIONS.length; i++) if (COLLECTIONS[i].handle === handle) return COLLECTIONS[i];
    return null;
  }

  var COLLECTION_ALIASES = {
    local: 'local-uae', uae: 'local-uae', emirati: 'local-uae', organic: 'organic-food', 'new': 'new-arrivals',
    latest: 'new-arrivals', arrivals: 'new-arrivals', popular: 'best-sellers', bestsellers: 'best-sellers',
    bestseller: 'best-sellers', bestselling: 'best-sellers', top: 'best-sellers', recommend: 'best-sellers',
    recommended: 'best-sellers', recommendation: 'best-sellers', recommendations: 'best-sellers', trending: 'trending',
    express: 'express', '1hr': 'express', fast: 'express', quick: 'express', urgent: 'express', bulk: 'bulk-buy',
    wholesale: 'bulk-buy', dairy: 'dairy', milk: 'dairy', eggs: 'eggs-cheese', egg: 'eggs-cheese', cheese: 'eggs-cheese',
    dates: 'dates', nuts: 'nuts-dried-fruits', nut: 'nuts-dried-fruits', healthy: 'healthy-pouches',
    pouches: 'healthy-pouches', pouch: 'healthy-pouches', snacks: 'healthy-pouches', snack: 'healthy-pouches',
    platter: 'ambrosia-platters', platters: 'ambrosia-platters', bouquet: 'ambrosia-bouquets',
    bouquets: 'ambrosia-bouquets', birthday: 'ambrosia-occasions', birthdays: 'ambrosia-occasions',
    anniversary: 'ambrosia-occasions', wedding: 'ambrosia-occasions', party: 'ambrosia-occasions',
    parties: 'ambrosia-occasions', celebration: 'ambrosia-occasions', celebrations: 'ambrosia-occasions',
    occasion: 'ambrosia-occasions', occasions: 'ambrosia-occasions', eid: 'ambrosia-eid', ramadan: 'ambrosia-ramadan',
    iftar: 'ambrosia-ramadan', christmas: 'ambrosia-christmas', xmas: 'ambrosia-christmas',
    valentine: 'ambrosia-valentines', valentines: 'ambrosia-valentines', mum: 'ambrosia-mothers-day',
    mom: 'ambrosia-mothers-day', mother: 'ambrosia-mothers-day', mothers: 'ambrosia-mothers-day'
  };
  function own(map, k) { return Object.prototype.hasOwnProperty.call(map, k) ? map[k] : null; }

  var COLLECTION_PHRASES = {
    'made uae': 'local-uae', 'new arrivals': 'new-arrivals', 'new arrival': 'new-arrivals',
    'best sellers': 'best-sellers', 'best seller': 'best-sellers', 'best selling': 'best-sellers',
    'top sellers': 'best-sellers', 'top selling': 'best-sellers', 'most popular': 'best-sellers', '1 hour': 'express',
    'one hour': 'express', '1 hr': 'express', 'dried fruit': 'nuts-dried-fruits', 'dried fruits': 'nuts-dried-fruits',
    'party platter': 'ambrosia-platters', 'party platters': 'ambrosia-platters', 'fruit platter': 'ambrosia-platters',
    'fruit platters': 'ambrosia-platters', 'flower bouquet': 'ambrosia-flowers', 'flower bouquets': 'ambrosia-flowers',
    'flowers bouquet': 'ambrosia-flowers', 'mothers day': 'ambrosia-mothers-day', 'mother day': 'ambrosia-mothers-day',
    'womens day': 'ambrosia-mothers-day', 'women day': 'ambrosia-mothers-day', 'valentines day': 'ambrosia-valentines',
    'valentine day': 'ambrosia-valentines'
  };
  var COLLECTION_COMMANDS = set(['bulk', 'wholesale', 'local', 'uae', 'emirati', 'organic']);

  // ---- recipes ---------------------------------------------------------------

  function recipe(name, ingredients, aliases, article) {
    var r = { name: name, ingredients: ingredients, aliases: aliases, article: article == null ? 'a ' : article };
    r.dish = r.article + name;
    r.message = 'Ideas for ' + r.dish;
    r.label = cap(name) + ' ideas';
    return r;
  }
  var RECIPES = [
    recipe('fruit salad', ['strawberry', 'kiwi', 'banana', 'blueberry'], ['fruit salad', 'fruits salad', 'fruit salads']),
    recipe('smoothie', ['banana', 'blueberry', 'strawberry', 'mango'], ['smoothie', 'smoothies', 'smoothy']),
    recipe('green salad', ['lettuce', 'cucumber', 'tomato', 'capsicum'], ['green salad', 'garden salad', 'salad', 'salads']),
    recipe('guacamole', ['avocado', 'tomato', 'onion', 'lime'], ['guacamole', 'guac'], ''),
    recipe('BBQ', ['kofta', 'tawouk', 'corn', 'tomato'], ['bbq', 'bbqs', 'barbecue', 'barbeque', 'grill', 'grilling']),
    recipe('breakfast', ['banana', 'blueberry', 'raspberry', 'kiwi'], ['breakfast', 'brunch'], '')
  ];
  var DISH_TRIGGERS = set(['recipe', 'recipes', 'idea', 'ideas', 'make', 'making', 'cook', 'cooking', 'prepare', 'preparing',
    'ingredient', 'ingredients', 'recommend', 'suggest', 'suggestion', 'suggestions', 'inspiration']);
  var IDEAS_L = ['recipe', 'recipes', 'idea', 'ideas', 'cook', 'cooking', 'make', 'inspiration', 'meal', 'meals'];
  var IDEAS_TRIGGERS = set(IDEAS_L);
  var IDEAS_FILLER = set(IDEAS_L, ['making', 'dinner', 'lunch', 'tonight', 'dish', 'dishes', 'something', 'anything', 'food',
    'easy', 'quick', 'simple', 'healthy', 'new', 'good', 'tasty', 'nice', 'few', 'more', 'other', 'suggest', 'suggestion',
    'suggestions', 'will', 'shall', 'recommend']);
  var DETERMINERS = set(['a', 'an', 'my', 'the', 'some', 'our']);

  // ---- contact, payment, delivery ------------------------------------------

  var CONTACT_L = ['contact', 'phone', 'telephone', 'call', 'email', 'mail', 'whatsapp', 'complaint', 'complaints', 'complain',
    'refund', 'refunds', 'helpline', 'hotline', 'agent', 'human', 'representative', 'careline', 'feedback', 'tracking'];
  var CONTACT_WORDS = set(CONTACT_L);
  var CONTACT_PHRASES = ['customer service', 'customer care', 'customer support', 'customer services', 'talk to', 'talk with',
    'speak to', 'speak with', 'in touch', 'reach you', 'order status'];
  var ISSUE_L = ['late', 'missing', 'wrong', 'damaged', 'problem', 'problems', 'issue', 'issues', 'delayed', 'broken',
    'rotten', 'spoiled', 'spoilt', 'cancel', 'cancelled', 'canceled', 'track'];
  var ISSUE_WORDS = set(ISSUE_L);
  var ORDER_WORDS = set(['order', 'orders', 'delivery', 'delivered', 'item', 'items', 'product', 'products', 'driver', 'rider',
    'package', 'parcel']);
  var PARCEL_WORDS = set(['order', 'orders', 'parcel', 'package']);
  var NOT_YET = set(['didnt', 'hasnt', 'havent', 'not', 'never', 'still', 'yet']);
  var ARRIVED = set(['arrived', 'arrive', 'delivered', 'came', 'come', 'received', 'receive']);
  var WEAK_CONTACT_L = ['support', 'number', 'address', 'location', 'located', 'hours', 'timings', 'timing', 'branch',
    'branches', 'outlet', 'outlets'];
  var WEAK_CONTACT = set(WEAK_CONTACT_L);
  var OPEN_L = ['open', 'opening', 'close', 'closing', 'closed'];
  var OPEN_WORDS = set(OPEN_L);
  var CONTACT_FILLER = set(WEAK_CONTACT_L, OPEN_L, ['store', 'shop', 'stores', 'shops', 'fresh', 'market', 'working',
    'business', 'office', 'main', 'customer', 'based', 'visit', 'physical', 'contact', 'details', 'detail', 'info',
    'information', 'time', 'times', 'near', 'nearest', 'exact', 'full', 'will', 'be', 'tomorrow']);
  var PAYMENT_L = ['payment', 'payments', 'cod', 'visa', 'mastercard', 'amex', 'paypal', 'tabby', 'tamara', 'applepay', 'gpay',
    'installments', 'instalments'];
  var PAYMENT_WORDS = set(PAYMENT_L);
  var CARD_L = ['card', 'cards', 'cash', 'credit', 'debit'];
  var CARD_WORDS = set(CARD_L);
  var GREETING_CARD = set(['gift', 'greeting', 'greetings', 'birthday', 'message', 'note', 'anniversary', 'wedding', 'eid',
    'christmas', 'valentine', 'valentines', 'ramadan']);
  var PAY_HOW = set(['by', 'with', 'using', 'via', 'on', 'through', 'online', 'method', 'methods', 'option', 'options', 'ways',
    'way', 'accept', 'accepted']);
  var DELIVERY_L = ['delivery', 'deliveries', 'deliver', 'delivers', 'delivering', 'delivered', 'shipping', 'ship', 'ships',
    'shipment', 'dispatch', 'courier', 'arrive', 'arrives', 'arrival', 'arriving'];
  var DELIVERY_WORDS = set(DELIVERY_L);

  // ---- favourites, thanks, help, brands -------------------------------------

  var FAV_L = ['favourite', 'favourites', 'favorite', 'favorites', 'fav', 'favs', 'fave', 'faves', 'wishlist', 'wishlists',
    'saved', 'liked', 'hearted'];
  var FAV_WORDS = set(FAV_L);
  var THANKS_L = ['thanks', 'thank', 'thx', 'thnx', 'ty', 'cheers', 'appreciated', 'appreciate', 'shukran'];
  var THANKS_WORDS = set(THANKS_L);
  var BYE_L = ['bye', 'goodbye', 'byebye', 'cya', 'goodnight', 'khalas'];
  var BYE_WORDS = set(BYE_L);
  var THANKS_FILLER = set(THANKS_L, BYE_L, ['so', 'much', 'very', 'lot', 'lots', 'alot', 'great', 'perfect', 'awesome', 'cool',
    'nice', 'good', 'see', 'later', 'again', 'help', 'all', 'thats', 'will', 'done', 'its', 'fine', 'day', 'night',
    'wonderful', 'mate', 'buddy', 'dear', 'assistant', 'bot', 'soon', 'enough', 'everything', 'was', 'helpful', 'really']);
  var GREET_L = ['hi', 'hello', 'hey', 'hiya', 'howdy', 'greetings', 'salam', 'salaam', 'marhaba', 'hola', 'yo', 'morning',
    'afternoon', 'evening'];
  var GREET_WORDS = set(GREET_L);
  var HELP_L = ['help', 'options', 'option', 'menu', 'commands', 'assist', 'assistance', 'start'];
  var HELP_WORDS = set(HELP_L);
  var HELP_PHRASES = ['what can you do', 'what do you do', 'what can i ask', 'what can i do', 'how does this work',
    'how does it work', 'how do you work', 'how can you help', 'how can you assist', 'who are you', 'what are you'];
  var HELP_FILLER = set(GREET_L, HELP_L, ['there', 'assistant', 'bot', 'good', 'everyone', 'all', 'again', 'guys', 'dear',
    'friend', 'team', 'fresh', 'market', 'assalamu', 'assalam', 'alaikum', 'alaykum', 'wa', 'something', 'anything', 'else',
    'ask', 'work', 'works', 'this', 'does', 'out', 'available']);
  var BRAND_L = ['brand', 'brands'];
  var BRAND_WORDS = set(BRAND_L);
  var BRAND_FILLER = set(BRAND_L, ['sell', 'selling', 'carry', 'stock', 'stocked', 'love', 'loved', 'top', 'popular', 'best',
    'available', 'all', 'our', 'kind', 'kinds', 'type', 'types', 'different', 'favourite', 'favorite']);
  var BRANDS = [['Chiquita', 'Chiquita'], ['Zespri', 'Zespri'], ['Sebastiano', 'Sebastiano'], ['Jazz', 'Jazz'],
    ['Gems', 'Gems'], ['Fruitway', 'Fruitway'], ['Dazzle', 'Dazzle'], ['Thai Fresh', 'Thai'], ['Pink Lady', 'Pink Lady'],
    ['Juliet', 'Juliet']];

  // ---- cheapest, price, stock -----------------------------------------------

  var CHEAP_L = ['cheapest', 'cheap', 'cheaper', 'budget', 'affordable', 'inexpensive', 'economical', 'lowest', 'bargain'];
  var CHEAP_WORDS = set(CHEAP_L);
  var CHEAP_PHRASES = ['least expensive', 'low price', 'low cost', 'best price'];
  var CUR = '(?:aed|dhs|dh|dirhams|dirham)';
  var PRICE_LIMIT = new RegExp('(?:^|[^a-z])(?:under|below|less than|cheaper than|lower than|maximum|max|up to|upto|' +
    'at most|no more than|not more than|budget of|budget)\\s*(?:' + CUR + '\\.?\\s*)?(\\d+(?:[.,]\\d{1,2})?)' +
    '(?:\\s*' + CUR + '(?![a-z]))?|(?:^|[^\\d.,])(\\d+(?:[.,]\\d{1,2})?)\\s*' + CUR + '\\.?\\s+or\\s+(?:less|under|below)');
  var CHEAP_FILLER = set(CHEAP_L, ['least', 'expensive', 'low', 'price', 'prices', 'priced', 'cost', 'best', 'option',
    'options', 'one', 'ones', 'under', 'below', 'less', 'than', 'max', 'maximum', 'up', 'upto', 'most', 'aed', 'dhs', 'dh',
    'dirham', 'dirhams', 'products', 'product', 'items', 'available', 'right', 'only', 'something', 'anything']);
  var PRICE_L = ['price', 'prices', 'priced', 'pricing', 'cost', 'costs', 'costing'];
  var PRICE_WORDS = set(PRICE_L);
  var PRICE_FILLER = set(PRICE_L, ['much', 'does', 'per', 'each', 'current', 'currently', 'kg', 'kilo', 'unit', 'piece',
    'will', 'be']);
  var STOCK_L = ['stock', 'instock', 'available', 'availability', 'unavailable', 'restock', 'restocked'];
  var STOCK_WORDS = set(STOCK_L);
  var STOCK_FILLER = set(STOCK_L, ['sold', 'out', 'still', 'currently', 'right', 'back', 'yet', 'again', 'will', 'be', 'does',
    'they', 'them', 'left']);

  // ---- all categories ---------------------------------------------------------

  var ALLCAT_L = ['categories', 'category', 'departments', 'department', 'sections', 'aisles', 'catalogue', 'catalog',
    'browse', 'sell', 'selling'];
  var ALLCAT_WORDS = set(ALLCAT_L);
  var ALLCAT_PHRASES = ['what do you have', 'what have you got', 'what you have', 'what do you got'];
  var ALLCAT_FILLER = set(CATEGORY_FILLER_L, ALLCAT_L, ['range', 'store', 'everything', 'kinds', 'kind', 'types', 'type',
    'main', 'stuff', 'things', 'here', 'available', 'other']);

  var STEERING = set(REMOVE, CLEAR, ['cart'], CHECKOUT, OFFER, UNITS, ['half', 'quarter'], NEG, QSTART,
    Object.keys(NUMBER_WORDS), FAV_L, CONTACT_L, ISSUE_L, WEAK_CONTACT_L, PAYMENT_L, CARD_L, DELIVERY_L, CHEAP_L, PRICE_L,
    STOCK_L, BRAND_L, THANKS_L, BYE_L, GREET_L, HELP_L, ['free', 'add', 'buy', 'put', 'order', 'take', 'out', 'more', 'and',
      'x', 'dozen', 'wish', 'much', 'sold', 'ingredient', 'ingredients', 'recipe', 'recipes']);

  var YES_WORDS = set(['yes', 'yeah', 'yea', 'yep', 'yup', 'ya', 'sure', 'ok', 'okay', 'confirm', 'confirmed', 'absolutely',
    'definitely']);
  var NO_WORDS = set(['no', 'nope', 'nah', 'cancel', 'dont', 'stop', 'keep', 'wait']);
  var ANSWER_FILLER = set(CLEAR_FILLER_L, ['please', 'pls', 'it', 'my', 'the', 'i', 'am', 'im', 'do', 'go', 'ahead', 'of',
    'course', 'thanks', 'thank', 'you', 'that', 'them', 'mind', 'never', 'now', 'not', 'just', 'want', 'to']);

  var REMOVE_FILLER = set(REMOVE, ['take', 'out', 'from', 'off', 'rid', 'cart', 'bag', 'trolley', 'all', 'item', 'items',
    'them', 'those', 'these', 'unit', 'units', 'pack', 'packs', 'x']);

  var EXPRESS_STATUS = set(['open', 'opens', 'opening', 'close', 'closes', 'closed', 'closing', 'available', 'availability',
    'area', 'zone', 'hours', 'time', 'times', 'now', 'today', 'tonight', 'running', 'cover', 'covers', 'reach', 'eta', 'long',
    'until', 'till']);
  var EXPRESS_QSTART = set(['is', 'are', 'can', 'could', 'do', 'does', 'will', 'when', 'how']);

  // ---- parsing ------------------------------------------------------------------

  function isPlainWord(word) {
    return !!word && !/\d/.test(word) && !has(STOP, word) && !has(STEERING, word);
  }

  /** Lower-case words; an apostrophe joins ("what's" -> "whats"). */
  function words(text) {
    return String(text || '').toLowerCase().replace(/['’`]/g, '')
      .split(/[^\p{L}\p{N}]+/u).filter(function (w) { return w.length > 0; });
  }

  function basketIsCart(tokens, at) {
    if (at === 0) return true;
    var before = tokens[at - 1];
    if (has(BASKET_LEAD, before)) return true;
    return before === 'a' && at >= 2 && (tokens[at - 2] === 'to' || tokens[at - 2] === 'in' || tokens[at - 2] === 'into');
  }
  function cartTokens(tokens) {
    return tokens.map(function (w, i) { return w === 'basket' && basketIsCart(tokens, i) ? 'cart' : w; });
  }

  function matchesAt(tokens, at, parts) {
    if (at + parts.length > tokens.length) return false;
    for (var j = 0; j < parts.length; j++) if (tokens[at + j] !== parts[j]) return false;
    return true;
  }
  function hasPhrase(tokens, phrase) {
    var parts = phrase.split(' ');
    for (var i = 0; i + parts.length <= tokens.length; i++) if (matchesAt(tokens, i, parts)) return true;
    return false;
  }

  function quantityOf(word) {
    var n = intOf(word);
    if (n != null) return n;
    if (own(NUMBER_WORDS, word) != null) return NUMBER_WORDS[word];
    if (word === 'dozen') return 12;
    var m = /^(\d+)x$/.exec(word) || /^x(\d+)$/.exec(word);
    return m ? parseInt(m[1], 10) : null;
  }

  function onlyOffer(w) {
    return has(STOP, w) || has(OFFER_WORDS, w) || ['add', 'buy', 'get', 'free', 'order'].indexOf(w) >= 0 ||
      quantityOf(w) != null;
  }

  function singularWord(word) {
    if (word.length <= 3) return word;
    if (/ies$/.test(word)) return word.slice(0, -3) + 'y';
    if (/oes$/.test(word)) return word.slice(0, -2);
    if (/s$/.test(word) && !/ss$/.test(word) && !/us$/.test(word)) return word.slice(0, -1);
    return word;
  }
  function singular(query) { return query.split(' ').map(singularWord).join(' '); }

  /** true for yes, false for no, null for anything else (a new request). */
  function confirmation(text) {
    var tokens = cartTokens(words(text));
    if (!tokens.length) return null;
    var yes = any(tokens, inSet(YES_WORDS)) || hasPhrase(tokens, 'do it') || hasPhrase(tokens, 'go ahead');
    var no = any(tokens, inSet(NO_WORDS)) || hasPhrase(tokens, 'never mind') || hasPhrase(tokens, 'not now');
    if (yes === no) return null;
    var only = all(tokens, function (w) { return has(ANSWER_FILLER, w) || has(YES_WORDS, w) || has(NO_WORDS, w); });
    return only ? yes : null;
  }

  function addTrigger(tokens) {
    for (var i = 0; i < tokens.length; i++) {
      var w = tokens[i];
      var before = tokens.slice(0, i);
      if (w === 'add') return i;
      if (w === 'buy' && all(before, inSet(POLITE))) return i;
      if (w === 'order' && all(before, inSet(POLITE)) && !any(tokens, inSet(ORDER_QUESTION))) return i;
      if ((w === 'put' || w === 'get') && any(tokens.slice(i + 1), inSet(CART_WORDS))) return i;
    }
    return -1;
  }

  function parseAdd(text) {
    var lower = String(text).toLowerCase();
    var measure = measureTest(lower);
    var tokens = cartTokens(words(measureStrip(lower)));
    var rest = tokens.slice(addTrigger(tokens) + 1);
    var quantity = 1, numberSeen = false, moreItems = false, product = [];
    for (var i = 0; i < rest.length; i++) {
      var w = rest[i];
      if (has(FRACTION_WORDS, w) || has(UNIT_WORDS, w)) { measure = true; continue; }
      var n = quantityOf(w);
      if (n != null && !numberSeen) {
        numberSeen = true;
        quantity = Math.max(1, Math.min(MAX_ADD, n));
        continue;
      }
      if (product.length) {
        var next = i + 1 < rest.length ? rest[i + 1] : null;
        var secondItem = intOf(w) != null ||
          (w === 'and' && next != null && (quantityOf(next) != null || next === 'a' || next === 'an' || next === 'some'));
        var otherRequest = w === 'and' && any(rest.slice(i + 1), function (x) {
          return has(OFFER_WORDS, x) || has(CART_WORDS, x) || has(CHECKOUT_WORDS, x) || x === 'check';
        });
        if (secondItem || otherRequest) { moreItems = true; break; }
      }
      if (has(STOP, w) || has(ADD_FILLER, w) || has(OFFER_WORDS, w)) continue;
      product.push(w);
    }
    return { type: 'add', quantity: quantity, query: product.join(' '), measureAsked: measure, moreItems: moreItems };
  }

  function parseRemove(text) {
    var tokens = cartTokens(words(measureStrip(String(text).toLowerCase())));
    var quantity = null, product = [];
    for (var i = 0; i < tokens.length; i++) {
      var w = tokens[i];
      if (has(UNIT_WORDS, w) || has(FRACTION_WORDS, w)) continue;
      if (!product.length && quantity == null) {
        var n = quantityOf(w);
        if (n == null && (w === 'a' || w === 'an')) n = 1;
        if (n != null) { quantity = n < 1 ? 1 : n; continue; }
      }
      if (has(STOP, w) || has(REMOVE_FILLER, w) || has(NEGATIONS, w)) continue;
      product.push(w);
    }
    return { type: 'remove', query: product.join(' '), quantity: quantity };
  }

  function isContact(tokens) {
    if (any(tokens, inSet(CONTACT_WORDS))) return true;
    if (any(CONTACT_PHRASES, function (p) { return hasPhrase(tokens, p); })) return true;
    if (tokens.indexOf('track') >= 0 && tokens.indexOf('order') >= 0) return true;
    var asksWhere = tokens.indexOf('where') >= 0 || tokens.indexOf('status') >= 0;
    if (asksWhere && any(tokens, inSet(PARCEL_WORDS))) return true;
    if (tokens.indexOf('delivery') >= 0 && (tokens.indexOf('status') >= 0 ||
      (tokens.indexOf('where') >= 0 && tokens.indexOf('my') >= 0))) return true;
    if (any(tokens, inSet(ISSUE_WORDS)) && any(tokens, inSet(ORDER_WORDS))) return true;
    return any(tokens, inSet(NOT_YET)) && any(tokens, inSet(ARRIVED));
  }

  function asksExpress(tokens) {
    var named = tokens.indexOf('express') >= 0 || tokens.indexOf('1hr') >= 0 ||
      any(['1 hour', 'one hour', '1 hr', 'an hour', '60 min', '60 mins', '60 minutes'],
        function (p) { return hasPhrase(tokens, p); });
    if (!named) return false;
    return any(tokens, inSet(DELIVERY_WORDS)) || any(tokens, inSet(EXPRESS_STATUS)) ||
      (tokens.length > 0 && has(EXPRESS_QSTART, tokens[0]));
  }

  function isPayment(tokens) {
    if (any(tokens, inSet(PAYMENT_WORDS))) return true;
    if (any(tokens, inSet(CARD_WORDS)) && !any(tokens, inSet(GREETING_CARD))) return true;
    if (any(['apple pay', 'google pay', 'samsung pay'], function (p) { return hasPhrase(tokens, p); })) return true;
    var payAt = -1;
    for (var i = 0; i < tokens.length; i++) if (tokens[i] === 'pay' || tokens[i] === 'paying') { payAt = i; break; }
    if (payAt < 0) return false;
    if (any(tokens, inSet(PAY_HOW))) return true;
    var howAt = tokens.indexOf('how');
    return howAt >= 0 && howAt < payAt && tokens.indexOf('much') < 0;
  }

  function parseCheapest(text, tokens) {
    var lower = String(text).toLowerCase();
    var limit = PRICE_LIMIT.exec(lower);
    var asked = limit != null || any(tokens, inSet(CHEAP_WORDS)) ||
      any(CHEAP_PHRASES, function (p) { return hasPhrase(tokens, p); });
    if (!asked) return null;
    var maxFils = null, rest = lower;
    if (limit) {
      var amount = (limit[1] || limit[2]).replace(',', '.');
      maxFils = Math.round(parseFloat(amount) * 100);
      rest = lower.slice(0, limit.index) + ' ' + lower.slice(limit.index + limit[0].length);
    }
    var query = words(rest).filter(function (w) {
      return !has(STOP, w) && !has(COMMAND_FILLER, w) && !has(CHEAP_FILLER, w) && !has(UNIT_WORDS, w) && intOf(w) == null;
    }).join(' ');
    return { type: 'cheapest', query: query, maxFils: maxFils };
  }

  function findRecipe(tokens) {
    for (var i = 0; i < tokens.length; i++) {
      var best = null, bestLength = 0;
      for (var r = 0; r < RECIPES.length; r++) {
        for (var a = 0; a < RECIPES[r].aliases.length; a++) {
          var parts = RECIPES[r].aliases[a].split(' ');
          if (parts.length > bestLength && matchesAt(tokens, i, parts)) { best = RECIPES[r]; bestLength = parts.length; }
        }
      }
      if (best) return { recipe: best, at: i };
    }
    return null;
  }

  function parseRecipe(tokens, meaningful) {
    var found = findRecipe(tokens);
    if (found) {
      var before = found.at - 1;
      while (before >= 0 && has(DETERMINERS, tokens[before])) before--;
      var forDish = before >= 0 && tokens[before] === 'for';
      if (forDish || any(tokens, inSet(DISH_TRIGGERS))) return { type: 'recipe', recipe: found.recipe };
      return null;
    }
    if (!any(tokens, inSet(IDEAS_TRIGGERS))) return null;
    var withAt = -1;
    for (var i = 0; i < tokens.length; i++) if (tokens[i] === 'with' || tokens[i] === 'using') { withAt = i; break; }
    if (withAt >= 0) {
      for (var j = withAt + 1; j < tokens.length; j++) {
        var ingredient = singular(tokens[j]);
        for (var r = 0; r < RECIPES.length; r++) {
          if (RECIPES[r].ingredients.indexOf(ingredient) >= 0) return { type: 'recipe', recipe: RECIPES[r] };
        }
      }
    }
    if (all(meaningful, inSet(IDEAS_FILLER))) return { type: 'recipeIdeas' };
    return null;
  }

  function collectionOrCategory(meaningful) {
    var named = meaningful.filter(function (w) { return !has(CATEGORY_FILLER, w) && !has(COLLECTION_FILLER, w); });
    if (!named.length) return null;
    var phrase = null, collection = null, category = null, i = 0;
    while (i < named.length) {
      var pair = i + 1 < named.length ? named[i] + ' ' + named[i + 1] : null;
      var ph = pair == null ? null : own(COLLECTION_PHRASES, pair);
      if (ph != null) { if (phrase == null) phrase = ph; i += 2; continue; }
      var shortcut = own(COLLECTION_ALIASES, named[i]);
      var cat = own(CATEGORY_ALIASES, named[i]);
      if (shortcut != null) { if (collection == null) collection = shortcut; }
      else if (cat != null) { if (category == null) category = cat; }
      else return null;
      i++;
    }
    var handle = phrase || collection || category;
    for (var c = 0; c < CATEGORIES.length; c++) {
      if (CATEGORIES[c].handle === handle) return { type: 'category', handle: handle, title: CATEGORIES[c].label, category: true };
    }
    var col = collectionBy(handle);
    return { type: 'collection', handle: handle, title: col.title };
  }

  function queryOf(meaningful, filler) {
    return meaningful.filter(function (w) { return !has(filler, w) && !has(UNIT_WORDS, w) && intOf(w) == null; }).join(' ');
  }

  function collectionIntent(handle) {
    return { type: 'collection', handle: handle, title: collectionBy(handle).title };
  }

  /** The first rule that matches wins (see assistant_intent.dart). */
  function parse(text) {
    var tokens = cartTokens(words(text));
    var hasCart = any(tokens, inSet(CART_WORDS));
    var named = tokens.filter(function (w) { return !has(STOP, w); });
    var firstNamed = named.length ? named[0] : null;
    var meaningful = tokens.filter(function (w) { return !has(STOP, w) && !has(COMMAND_FILLER, w); });

    // 1. empty the cart
    var clearAsked = any(tokens, inSet(CLEAR_WORDS)) ||
      (any(tokens, function (w) { return has(REMOVE_WORDS, w) || w === 'take'; }) &&
        any(tokens, function (w) { return w === 'everything' || w === 'all'; }));
    var question = tokens.length > 0 && has(QUESTION_STARTS, tokens[0]);
    if (clearAsked && !question && named.length && all(named, inSet(CLEAR_FILLER))) return { type: 'clearCart' };

    // 2. remove
    var takeOut = tokens.indexOf('take') >= 0 && tokens.indexOf('out') >= 0 && (hasCart || firstNamed === 'take');
    if (has(REMOVE_WORDS, firstNamed) || (hasCart && any(tokens, inSet(REMOVE_WORDS))) || takeOut ||
      hasPhrase(tokens, 'get rid of')) {
      if (any(tokens, inSet(FAV_WORDS))) return { type: 'favourites' };
      return parseRemove(text);
    }

    // 3. a command to add
    var addAt = addTrigger(tokens);
    if (addAt >= 0) {
      if ((any(tokens, inSet(OFFER_WORDS)) || tokens.indexOf('free') >= 0) && all(tokens, onlyOffer)) {
        return { type: 'offers' };
      }
      var command = !has(QUESTION_STARTS, tokens[0]) && !any(tokens.slice(0, addAt), inSet(NEGATIONS));
      if (command) {
        if (any(tokens, inSet(FAV_WORDS)) || hasPhrase(tokens, 'wish list')) return { type: 'favourites' };
        var rec = findRecipe(tokens);
        if (rec && any(tokens, function (w) {
          return w === 'ingredients' || w === 'ingredient' || w === 'recipe' || w === 'everything';
        })) return { type: 'recipe', recipe: rec.recipe };
        var add = parseAdd(text);
        var addWords = add.query.split(' ');
        if (!hasCart && add.query && all(addWords, inSet(COLLECTION_COMMANDS))) {
          return collectionIntent(COLLECTION_ALIASES[addWords[0]]);
        }
        return add;
      }
    }

    // 4. customer service; 5. payment; 5b. Express questions
    if (isContact(tokens)) return { type: 'contact' };
    if (isPayment(tokens)) return { type: 'payment' };
    if (asksExpress(tokens)) return { type: 'express' };

    // 6. delivery
    if (any(tokens, inSet(DELIVERY_WORDS)) || hasPhrase(tokens, 'same day') || tokens.indexOf('cutoff') >= 0 ||
      hasPhrase(tokens, 'cut off') || (tokens.indexOf('when') >= 0 && any(tokens, inSet(PARCEL_WORDS))) ||
      (tokens.indexOf('minimum') >= 0 && any(tokens, inSet(set(['order', 'orders', 'spend', 'purchase', 'amount', 'cart',
        'value'])))) ||
      (tokens.indexOf('address') >= 0 && any(tokens, inSet(set(['my', 'change', 'update', 'new', 'different']))))) {
      return { type: 'delivery' };
    }

    // 7. checkout; 8. cart
    if (any(tokens, inSet(CHECKOUT_WORDS)) || hasPhrase(tokens, 'check out')) return { type: 'checkout' };
    if (hasCart) return any(tokens, inSet(OPEN_CART_WORDS)) ? { type: 'cart', open: true } : { type: 'cart' };

    // 9. favourites
    if (!any(tokens, inSet(BRAND_WORDS)) && (any(tokens, inSet(FAV_WORDS)) || hasPhrase(tokens, 'wish list') ||
      hasPhrase(tokens, 'my list'))) return { type: 'favourites' };

    // 10. offers
    if (any(tokens, inSet(OFFER_WORDS))) return { type: 'offers' };

    // 11. where the store is, when it is open
    var contactAsked = any(tokens, inSet(WEAK_CONTACT)) ||
      (any(tokens, inSet(OPEN_WORDS)) && any(tokens, inSet(set(['when', 'time', 'times', 'hours', 'today', 'now',
        'tomorrow', 'you', 'store', 'shop'])))) ||
      (tokens.indexOf('where') >= 0 && any(tokens, inSet(set(['store', 'shop', 'you', 'located', 'based']))));
    if (contactAsked && all(meaningful, inSet(CONTACT_FILLER))) return { type: 'contact' };

    // 12. thanks / bye
    var bye = any(tokens, inSet(BYE_WORDS)) || hasPhrase(tokens, 'see you') || hasPhrase(tokens, 'good night');
    if ((any(tokens, inSet(THANKS_WORDS)) || bye) && all(meaningful, inSet(THANKS_FILLER))) {
      return { type: 'thanks', farewell: bye };
    }

    // 13. help / greeting
    var helpAsked = any(tokens, inSet(HELP_WORDS)) || any(HELP_PHRASES, function (p) { return hasPhrase(tokens, p); });
    if ((helpAsked || any(tokens, inSet(GREET_WORDS))) && all(meaningful, inSet(HELP_FILLER))) {
      return { type: 'help', greeting: !helpAsked };
    }

    // 14. brands
    if (any(tokens, inSet(BRAND_WORDS)) && all(meaningful, inSet(BRAND_FILLER))) return { type: 'brands' };

    // 15. cheapest; 16. price; 17. stock
    var cheapest = parseCheapest(text, tokens);
    if (cheapest) return cheapest;
    if (hasPhrase(tokens, 'how much') || any(tokens, inSet(PRICE_WORDS))) {
      return { type: 'price', query: queryOf(meaningful, PRICE_FILLER) };
    }
    if (any(tokens, inSet(STOCK_WORDS)) || hasPhrase(tokens, 'sold out')) {
      return { type: 'stock', query: queryOf(meaningful, STOCK_FILLER) };
    }

    // 18. recipes
    var r = parseRecipe(tokens, meaningful);
    if (r) return r;

    // 19. all categories
    if ((any(tokens, inSet(ALLCAT_WORDS)) || any(ALLCAT_PHRASES, function (p) { return hasPhrase(tokens, p); })) &&
      all(meaningful, inSet(ALLCAT_FILLER))) return { type: 'allCategories' };

    // 20. a collection or a category
    var shortcut = collectionOrCategory(meaningful);
    if (shortcut) return shortcut;

    // 21. search ("zespri brand" searches for "zespri")
    var q = meaningful.filter(function (w) { return !has(BRAND_WORDS, w); });
    return { type: 'search', query: (q.length ? q : meaningful).join(' ') };
  }

  // ---- reply copy (assistant_brain.dart) ------------------------------------

  var MAX_PRODUCTS = 3;
  var MAX_RECIPE_PRODUCTS = 4;
  var RECIPE_SEARCH_WIDTH = 2;
  var EXPRESS_HOURS = '8 AM to 10 PM';
  var EXPRESS_CLOSE = '10 PM';

  var QUICK_OPTIONS = [
    { id: 'offers', label: "Today's offers", message: 'What is on offer?' },
    { id: 'categories', label: 'Categories', message: 'Show all categories' },
    { id: 'recipes', label: 'Recipe ideas', message: 'Recipe ideas' },
    { id: 'local', label: 'Local UAE', message: 'Show local UAE produce' },
    { id: 'gifts', label: 'Gifts & flowers', message: 'Gift ideas' },
    { id: 'bestsellers', label: 'Best sellers', message: 'What is popular?' },
    { id: 'cart', label: 'My cart', message: 'Open my cart' },
    { id: 'care', label: 'Customer care', message: 'Contact customer service' }
  ];
  var DEFAULT_SUGGESTIONS = ['What is on offer?', 'Show me berries', 'Add 2 cucumbers', 'Ideas for a fruit salad',
    'Cheapest avocado', 'Show local UAE produce', 'Gift ideas', "What's new?", 'Contact customer service', 'Open my cart'];

  var OFFERS_CHIP = 'What is on offer?';
  var POPULAR_CHIP = 'What is popular?';
  var CATEGORIES_CHIP = 'Show all categories';
  var CART_CHIP = 'Open my cart';
  var CHECKOUT_CHIP = 'Checkout';
  var EMPTY_CART_CHIP = 'Empty my cart';
  var BERRIES_CHIP = 'Show me berries';
  var DELIVERY_CHIP = 'Delivery information';
  var PAYMENT_CHIP = 'Payment methods';
  var CONTACT_CHIP = 'Contact customer service';
  var EXPRESS_CHIP = 'Show 1Hr Express';
  var EXPRESS_Q_CHIP = 'Is Express open?';
  var FRUIT_SALAD_CHIP = RECIPES[0].message;
  var START_CHIPS = [OFFERS_CHIP, BERRIES_CHIP, FRUIT_SALAD_CHIP];
  var YES_CLEAR_CHIP = 'Yes, empty my cart';
  var NO_CLEAR_CHIP = 'No, keep my cart';
  var ADD_ALL_CHIP = 'Add all to cart';

  var NETWORK_ERROR = 'I could not reach the store. Check your connection and try again.';
  var UNEXPECTED_ERROR = 'Sorry, something went wrong. Please try again.';
  var TRY_HINT = 'Try "Show me berries", "Find avocado" or "Add 2 cucumbers".';
  var FEES_TEXT = 'Any delivery fee is shown at checkout.';
  var CHOOSE_AREA = 'Choose your area with the "Deliver to" button at the top of the page';
  var OPTIONS_TEXT = 'Here is what I can help with. Tap an option or type your question.';

  var CART_LINK = { label: 'Open cart', url: '/cart' };
  var EXPRESS_LINK = { label: 'Shop Express items', url: '/collections/express' };
  var GIFT_LINKS = [
    { label: 'Open Flowers', url: '/collections/ambrosia-flowers' },
    { label: 'Open Fruit Bouquets', url: '/collections/ambrosia-bouquets' },
    { label: 'Open Special Occasions', url: '/collections/ambrosia-occasions' }
  ];
  var DEALS = [{ title: "Today's Top Deals", handle: 'fresh-meat' }, { title: 'Best Deals', handle: 'best-deals' }];

  var SERVICE_WORDS = set(['order', 'orders', 'minimum', 'account', 'accounts', 'login', 'logout', 'signin', 'signup',
    'password', 'refund', 'refunds', 'invoice', 'invoices', 'receipt', 'receipts', 'history', 'status']);

  /** "AED 1,250.00" (a no-break space after AED). */
  function formatMoney(fils) {
    var n = Math.round(Number(fils) || 0);
    var neg = n < 0;
    n = Math.abs(n);
    var whole = String(Math.floor(n / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    var fraction = String(n % 100);
    if (fraction.length < 2) fraction = '0' + fraction;
    return (neg ? '-' : '') + 'AED ' + whole + '.' + fraction;
  }

  function collectionLink(label, handle) { return { label: label, url: '/collections/' + handle }; }
  function searchLink(query, label) {
    return { label: label || 'See all results', url: '/search?q=' + encodeURIComponent(query) + '&type=product' };
  }

  function joinAnd(items) {
    if (!items.length) return '';
    if (items.length === 1) return items[0];
    return items.slice(0, -1).join(', ') + ' and ' + items[items.length - 1];
  }

  /** At most three plain words of a title, safe in a chip; null if none. */
  function shortName(title) {
    var kept = [];
    var pieces = String(title || '').match(/[\p{L}\p{N}'’]+/gu) || [];
    for (var i = 0; i < pieces.length; i++) {
      if (isPlainWord(words(pieces[i]).join(''))) kept.push(pieces[i]);
      if (kept.length === 3) break;
    }
    return kept.length ? kept.join(' ') : null;
  }
  function plainQuery(query) {
    var kept = words(query).filter(isPlainWord);
    return kept.length ? kept.join(' ') : null;
  }
  function chips(items) {
    var out = [];
    for (var i = 0; i < items.length; i++) {
      var c = items[i];
      if (!c || out.indexOf(c) >= 0) continue;
      out.push(c);
      if (out.length === 5) break;
    }
    return out;
  }
  function addChip(product, more) {
    var name = product ? shortName(product.title) : null;
    return name ? 'Add 1 ' + (more ? 'more ' : '') + name : null;
  }
  function priceChip(product) {
    var name = product ? shortName(product.title) : null;
    return name ? 'How much is ' + name + '?' : null;
  }
  function cheapestChip(query) { var p = plainQuery(query); return p ? 'Cheapest ' + p : null; }
  function stockChip(query) { var p = plainQuery(query); return p ? 'Is ' + p + ' in stock?' : null; }
  function removeChip(line) { var n = line ? shortName(line.title) : null; return n ? 'Remove ' + n : null; }
  function chipsFor(list, product) {
    var map = {};
    if (!product) return map;
    [addChip(product), addChip(product, true), priceChip(product)].forEach(function (c) {
      if (c && list.indexOf(c) >= 0) map[c] = product;
    });
    return map;
  }

  function firstAvailable(products) {
    for (var i = 0; i < products.length; i++) if (products[i].available) return products[i];
    return null;
  }
  function price(p) { return Number(p.priceFils) || 0; }
  function cheapestAvailable(products) {
    var best = null;
    products.forEach(function (p) { if (p.available && (!best || price(p) < price(best))) best = p; });
    return best;
  }
  function onSale(p) { return p.compareAtFils != null && Number(p.compareAtFils) > price(p); }
  function salePercent(p) {
    if (!onSale(p)) return 0;
    var pc = Math.round((p.compareAtFils - price(p)) * 100 / p.compareAtFils);
    return pc < 1 ? 0 : pc;
  }
  function titleHas(title, ingredient) {
    var wanted = singular(ingredient);
    return any(words(title), function (w) { return w === ingredient || singular(w) === wanted; });
  }
  function titleNames(title, query) { return all(words(query), function (w) { return titleHas(title, w); }); }
  function names(product, ws) {
    var text = [product.title, product.vendor || ''].concat(product.tags || []).join(' ').toLowerCase();
    return all(ws, function (w) { return text.indexOf(w) >= 0 || text.indexOf(singular(w)) >= 0; });
  }
  function naming(products, query) {
    var wanted = words(query);
    if (!wanted.length) return products;
    return products.filter(function (p) { return names(p, wanted); });
  }
  function pickToAdd(results, query) {
    return cheapestAvailable(results.filter(function (p) { return titleNames(p.title, query); })) ||
      cheapestAvailable(naming(results, query)) || firstAvailable(results);
  }
  function lineHas(line, wanted) {
    var have = words(line.title).map(singular);
    return all(wanted, function (w) {
      return any(have, function (h) { return h === w || (w === 'berry' && h.length >= w.length && h.slice(-w.length) === w); });
    });
  }
  function otherRecipes(r) {
    var at = RECIPES.indexOf(r), out = [];
    for (var i = 1; i < RECIPES.length; i++) out.push(RECIPES[(at + i) % RECIPES.length]);
    return out;
  }
  function publicProduct(p) {
    return {
      id: p.id, variantId: p.variantId, title: p.title, subtitle: p.subtitle || '', priceFils: p.priceFils,
      compareAtFils: p.compareAtFils == null ? null : p.compareAtFils, available: !!p.available, image: p.image || '',
      url: p.url || ''
    };
  }
  function sentence(s) { s = String(s || '').trim(); return !s ? '' : /[.!?]$/.test(s) ? s : s + '.'; }
  function lowerFirst(s) { return s ? s.charAt(0).toLowerCase() + s.slice(1) : s; }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }

  // ---- the brain --------------------------------------------------------------

  function create(store, config) {
    config = config || {};
    var storeName = config.storeName || 'Fresh Market';
    var phone = config.contactPhone || '800 1 627538';
    var email = config.contactEmail || 'care@freshmarket.ae';
    var greetingText = config.greeting || ('Hi, I am your ' + storeName + ' assistant. Ask me to find a product, ' +
      "open a category, add something to your cart or show today's offers.");
    var retryDelay = config.retryDelayMs == null ? 1000 : config.retryDelayMs;
    var contactText = 'You can reach ' + storeName + ' customer service on ' + phone + ' (toll-free) or ' + email +
      ', 7 days a week, 8am to 11pm. The store is in Ras Al Khor, Dubai.';
    var contactLinks = [
      { label: 'Call ' + phone, url: 'tel:' + phone.replace(/[^\d+]/g, '') },
      { label: 'Email us', url: 'mailto:' + email },
      { label: 'Contact page', url: '/pages/contact' }
    ];
    var last = {};

    // Wrapped so a reply knows whether it already changed the cart (no retry).
    function run(intent, target, ctx) {
      function find(query, limit) {
        return Promise.resolve(store.search(query, limit)).then(function (found) {
          found = found || [];
          if (found.length) return found;
          var s = singular(query);
          return s === query ? found : Promise.resolve(store.search(s, limit)).then(function (f) { return f || []; });
        });
      }
      function readCart() {
        return Promise.resolve(store.cart()).then(function (c) {
          c = c || {};
          return { items: c.items || [], itemCount: c.itemCount || 0, totalFils: c.totalFils || 0 };
        });
      }
      function summary(cart) {
        var n = cart.itemCount;
        return 'Your cart has ' + n + ' ' + (n === 1 ? 'item' : 'items') + ', subtotal ' + formatMoney(cart.totalFils) + '.';
      }
      function notFound(query) {
        return {
          text: 'I could not find anything for "' + query + '". ' + TRY_HINT + ' You can also ask "What is on offer?".',
          suggestions: [CATEGORIES_CHIP, OFFERS_CHIP, FRUIT_SALAD_CHIP]
        };
      }
      function fresh(saved) {
        if (!saved.handle) return Promise.resolve(saved);
        return Promise.resolve(store.product(saved.handle)).then(function (p) {
          if (!p) return Object.assign({}, saved, { available: false });
          return String(p.id) === String(saved.id) ? p : saved;
        }, function () { return saved; });
      }
      function delivery() {
        return Promise.resolve().then(function () { return store.delivery ? store.delivery() : null; })
          .then(function (d) { return d || {}; }, function () { return {}; });
      }
      function areaLabel(d) { return d.emirate && d.emirate !== d.area ? d.area + ', ' + d.emirate : d.area; }

      var handlers = {
        add: function () {
          var query = intent.query;
          if (!query) return { text: 'Tell me what to add, for example "Add 2 cucumbers".', suggestions: START_CHIPS };
          var results, product;
          var pick = target && !intent.measureAsked
            ? fresh(target).then(function (f) { results = [f]; product = f.available ? f : null; return null; })
            : find(query, 10).then(function (found) {
              results = found;
              if (!found.length) {
                return {
                  text: 'I could not find "' + query + '" in the store, so nothing was added. Try another name, for ' +
                    'example "Add 2 cucumbers".',
                  suggestions: [CATEGORIES_CHIP, OFFERS_CHIP, FRUIT_SALAD_CHIP]
                };
              }
              if (intent.measureAsked) {
                var shown = found.slice(0, MAX_PRODUCTS);
                var first = firstAvailable(shown);
                var sugg = chips([addChip(first), cheapestChip(query), CART_CHIP]);
                return {
                  text: 'I can only add whole packs, so nothing was added. Choose the size you want below.',
                  products: shown, links: [searchLink(query)], suggestions: sugg, _chipProducts: chipsFor(sugg, first)
                };
              }
              product = pickToAdd(found, query);
              return null;
            });
          return pick.then(function (early) {
            if (early) return early;
            if (!product) {
              return {
                text: results[0].title + ' is sold out right now, so nothing was added.', products: [results[0]],
                suggestions: chips([OFFERS_CHIP, CATEGORIES_CHIP, FRUIT_SALAD_CHIP])
              };
            }
            var before = 0;
            return readCart().then(function (cart) {
              before = qtyIn(cart, product.variantId);
              ctx.wrote = true;
              return store.add(product.variantId, intent.quantity);
            }).then(function (res) {
              if (!res || !res.ok) {
                return {
                  text: ('I could not add ' + product.title + ' to your cart. ' + sentence(res && res.error)).trim(),
                  products: [product], links: [CART_LINK], suggestions: [CART_CHIP, OFFERS_CHIP, CATEGORIES_CHIP]
                };
              }
              return readCart().then(function (cart) {
                var added = qtyIn(cart, product.variantId) - before;
                if (added < 0 || added > intent.quantity) added = intent.quantity;
                var only = intent.moreItems ? ' I add one product per message, so ask again for the rest.' : '';
                var priceText = formatMoney(product.priceFils) + (added > 1 ? ' each' : '');
                var sugg = chips([added > 0 ? addChip(product, true) : null, CART_CHIP, CHECKOUT_CHIP, FRUIT_SALAD_CHIP]);
                return {
                  text: (added > 0 ? 'Done. I added ' + added + ' × ' + product.title + ' to your cart at ' +
                    priceText + '.' : 'Your cart already holds the most it can of ' + product.title + '.') + only,
                  products: [product], links: [CART_LINK], suggestions: sugg, cartChanged: added > 0,
                  _chipProducts: chipsFor(sugg, product)
                };
              });
            });
          });
        },

        remove: function () {
          return readCart().then(function (cart) {
            if (!cart.items.length) {
              return { text: 'Your cart is empty, so there is nothing to remove.', suggestions: START_CHIPS };
            }
            var first = cart.items[0];
            if (!intent.query) {
              var example = shortName(first.title);
              return {
                text: (example ? 'Tell me what to remove, for example "Remove ' + example + '". '
                  : 'Tell me what to remove. ') + summary(cart),
                links: [CART_LINK], suggestions: chips([removeChip(first), CART_CHIP, EMPTY_CART_CHIP])
              };
            }
            var wanted = words(intent.query).map(singular);
            var matches = cart.items.filter(function (l) { return lineHas(l, wanted); });
            if (!matches.length) {
              return {
                text: 'I could not find ' + intent.query + ' in your cart. ' + summary(cart),
                links: [CART_LINK], suggestions: chips([removeChip(first), CART_CHIP, CHECKOUT_CHIP])
              };
            }
            var done, changes;
            ctx.wrote = true;
            if (intent.quantity != null) {
              var line = matches[0];
              var taken = Math.min(intent.quantity, line.quantity);
              done = 'Removed ' + taken + ' × ' + line.title + ' from your cart.';
              changes = store.setQuantity(line.key, line.quantity - taken);
            } else {
              done = 'Removed ' + joinAnd(matches.map(function (l) { return l.title; })) + ' from your cart.';
              changes = matches.reduce(function (p, l) {
                return p.then(function (r) { return r && !r.ok ? r : store.setQuantity(l.key, 0); });
              }, Promise.resolve({ ok: true }));
            }
            return Promise.resolve(changes).then(function (res) {
              if (!res || !res.ok) {
                return {
                  text: ('I could not change your cart. ' + sentence(res && res.error)).trim(),
                  links: [CART_LINK], suggestions: [CART_CHIP, CHECKOUT_CHIP, OFFERS_CHIP]
                };
              }
              return readCart().then(function (after) {
                if (!after.items.length) {
                  return { text: done + ' Your cart is empty now.', links: [CART_LINK], suggestions: START_CHIPS,
                    cartChanged: true };
                }
                return {
                  text: done + ' ' + summary(after), links: [CART_LINK], cartChanged: true,
                  suggestions: chips([CHECKOUT_CHIP, CART_CHIP, removeChip(after.items[0])])
                };
              });
            });
          });
        },

        clearCart: function () {
          return readCart().then(function (cart) {
            if (!cart.items.length) return { text: 'Your cart is already empty.', suggestions: START_CHIPS };
            var n = cart.itemCount;
            return {
              text: n === 1 ? 'This will remove the 1 item in your cart. Are you sure?'
                : 'This will remove all ' + n + ' items from your cart. Are you sure?',
              links: [{ label: 'Review cart', url: '/cart' }],
              suggestions: [YES_CLEAR_CHIP, NO_CLEAR_CHIP, CART_CHIP, CHECKOUT_CHIP],
              _clear: snapshot(cart)
            };
          });
        },

        checkout: function () {
          return readCart().then(function (cart) {
            if (!cart.items.length) {
              return {
                text: 'Your cart is empty, so there is nothing to check out yet. Ask me to add something first, for ' +
                  'example "Add 2 cucumbers".',
                suggestions: [OFFERS_CHIP, BERRIES_CHIP, 'Add 2 cucumbers']
              };
            }
            return {
              text: summary(cart) + ' Opening your cart, checkout is from there.', navigate: '/cart',
              links: [CART_LINK], suggestions: [PAYMENT_CHIP, DELIVERY_CHIP, CART_CHIP]
            };
          });
        },

        cart: function () {
          return readCart().then(function (cart) {
            var nav = intent.open ? { navigate: '/cart' } : {};
            if (!cart.items.length) {
              return assign({ text: 'Your cart is empty.' + (intent.open ? ' Opening the cart page.' : ''), links: [CART_LINK],
                suggestions: START_CHIPS }, nav);
            }
            return assign({
              text: summary(cart) + (intent.open ? ' Opening your cart.' : ''), links: [CART_LINK],
              suggestions: chips([CHECKOUT_CHIP, removeChip(cart.items[0]), EMPTY_CART_CHIP])
            }, nav);
          });
        },

        offers: function () {
          var failure = null;
          function load(h) {
            return Promise.resolve().then(function () { return store.collection(h, 20); })
              .then(function (l) { return l || []; }, function (e) { if (!failure) failure = e; return []; });
          }
          return Promise.all(DEALS.map(function (r) { return load(r.handle); })).then(function (loaded) {
            if (!loaded[0].length && !loaded[1].length && failure) throw failure;
            var seen = {}, sale = [];
            DEALS.forEach(function (rail, i) {
              loaded[i].forEach(function (p) {
                if (p.available && onSale(p) && !seen[p.id]) { seen[p.id] = true; sale.push({ rail: rail, p: p, i: sale.length }); }
              });
            });
            if (sale.length) {
              sale.sort(function (a, b) { return (salePercent(b.p) - salePercent(a.p)) || (a.i - b.i); });
              var shown = sale.slice(0, MAX_PRODUCTS);
              var best = shown[0].p;
              var pc = salePercent(best);
              var rails = [];
              shown.forEach(function (e) { if (rails.indexOf(e.rail) < 0) rails.push(e.rail); });
              var sugg = chips([addChip(best), POPULAR_CHIP, CART_CHIP]);
              return {
                text: 'These are on sale today.' + (pc > 0 ? ' The biggest saving is ' + pc + '% on ' + best.title + '.' : ''),
                products: shown.map(function (e) { return e.p; }),
                links: rails.map(function (r) { return collectionLink('See all ' + r.title, r.handle); }),
                suggestions: sugg, _chipProducts: chipsFor(sugg, best)
              };
            }
            var dealsLink = collectionLink('See all deals', 'best-deals');
            var list = loaded[1].slice(0, MAX_PRODUCTS);
            if (!list.length) {
              return {
                text: 'I could not find any offers in the store right now.', links: [dealsLink],
                suggestions: [POPULAR_CHIP, CATEGORIES_CHIP, FRUIT_SALAD_CHIP]
              };
            }
            var first = firstAvailable(list);
            var s2 = chips([addChip(first), POPULAR_CHIP, CATEGORIES_CHIP]);
            return {
              text: 'Nothing is marked down right now. Here are products from Best Deals.', products: list,
              links: [dealsLink], suggestions: s2, _chipProducts: chipsFor(s2, first)
            };
          });
        },

        collection: function () {
          var handle = intent.handle, title = intent.title;
          var extra = handle === 'hampers' ? GIFT_LINKS : [];
          var fallback = [CATEGORIES_CHIP, OFFERS_CHIP, FRUIT_SALAD_CHIP];
          return Promise.resolve().then(function () { return store.collection(handle, MAX_PRODUCTS); })
            .then(function (products) {
              products = products || [];
              var open = collectionLink('Open ' + title, handle);
              if (!products.length) {
                return { text: title + ' has no products in the store right now.', links: [open].concat(extra),
                  suggestions: fallback };
              }
              var shown = products.slice(0, MAX_PRODUCTS);
              var first = firstAvailable(shown);
              var sugg = chips([intent.category ? cheapestChip(title) : null, addChip(first), OFFERS_CHIP, CATEGORIES_CHIP]);
              var note = handle === 'express' ? delivery().then(expressNote) : Promise.resolve(null);
              return note.then(function (n) {
                return {
                  text: handle === 'hampers'
                    ? 'A few gift ideas from Hampers. You can also open Flowers, Fruit Bouquets or Special Occasions below.'
                    : (n ? n + ' ' : '') + 'A few products from ' + title + ':',
                  products: shown, links: [open].concat(extra), suggestions: sugg, _chipProducts: chipsFor(sugg, first)
                };
              });
            }, function (e) {
              if (!e || e.status !== 404) throw e;
              return { text: 'I could not find ' + title + ' in the store right now.', links: extra, suggestions: fallback };
            });
        },

        allCategories: function () {
          return Promise.resolve().then(function () { return store.collections ? store.collections() : null; })
            .then(function (l) { return l || []; }, function () { return []; })
            .then(function (live) {
              var handles = {};
              live.forEach(function (c) { if (c && c.handle) handles[c.handle] = true; });
              var tiles = CATEGORIES.filter(function (c) { return handles[c.handle]; });
              if (!tiles.length) tiles = CATEGORIES;
              return {
                text: 'Here are our categories.',
                links: tiles.map(function (c) { return collectionLink(c.label, c.handle); })
                  .concat([{ label: 'All categories', url: '/collections' }]),
                suggestions: ['Show local UAE produce', POPULAR_CHIP, 'Gift ideas', OFFERS_CHIP]
              };
            });
        },

        brands: function () {
          return {
            text: 'Here are the brands we love.',
            links: BRANDS.map(function (b) { return searchLink(b[1], b[0]); }),
            suggestions: [POPULAR_CHIP, CATEGORIES_CHIP, OFFERS_CHIP]
          };
        },

        search: function () {
          var query = intent.query;
          if (!query) return { text: 'Tell me a product or a category and I will look in the store. ' + TRY_HINT };
          if (all(words(query), inSet(SERVICE_WORDS))) {
            return {
              text: 'I cannot look up orders or accounts here. Customer service can help with that.',
              links: contactLinks, suggestions: [DELIVERY_CHIP, PAYMENT_CHIP, OFFERS_CHIP]
            };
          }
          return find(query, MAX_PRODUCTS).then(function (results) {
            if (!results.length) return notFound(query);
            var shown = results.slice(0, MAX_PRODUCTS);
            var first = firstAvailable(shown);
            var sugg = chips([cheapestChip(query), stockChip(query), addChip(first)]);
            return {
              text: results.length === 1 ? 'I found this for "' + query + '".' : 'Here is what I found for "' + query + '".',
              products: shown, links: [searchLink(query)], suggestions: sugg, _chipProducts: chipsFor(sugg, first)
            };
          });
        },

        cheapest: function () {
          var query = intent.query, max = intent.maxFils;
          if (!query) {
            return {
              text: max == null ? 'Tell me what to look for, for example "Cheapest avocado".'
                : 'Tell me what to look for under ' + formatMoney(max) + ', for example "Avocado under ' +
                Math.floor(max / 100) + '".',
              suggestions: ['Cheapest avocado', OFFERS_CHIP, CATEGORIES_CHIP]
            };
          }
          return find(query, 20).then(function (found) {
            if (!found.length) return notFound(query);
            var link = searchLink(query);
            var named = naming(found, query);
            var exact = named.length > 0;
            var results = exact ? named : found;
            var sorted = results.map(function (p, i) { return { p: p, i: i }; })
              .filter(function (e) { return e.p.available; })
              .sort(function (a, b) { return (price(a.p) - price(b.p)) || (a.i - b.i); })
              .map(function (e) { return e.p; });
            if (!sorted.length) {
              return {
                text: 'Everything I found for "' + query + '" is sold out right now.',
                products: results.slice(0, MAX_PRODUCTS), links: [link],
                suggestions: [OFFERS_CHIP, CATEGORIES_CHIP, FRUIT_SALAD_CHIP]
              };
            }
            var fitting = max == null ? sorted : sorted.filter(function (p) { return price(p) <= max; });
            if (!fitting.length) {
              var cheapest = sorted[0];
              var s1 = chips([addChip(cheapest), OFFERS_CHIP, CATEGORIES_CHIP]);
              return {
                text: 'Nothing for "' + query + '" is under ' + formatMoney(max) + ' right now. The cheapest is ' +
                  cheapest.title + ' at ' + formatMoney(cheapest.priceFils) + '.',
                products: [cheapest], links: [link], suggestions: s1, _chipProducts: chipsFor(s1, cheapest)
              };
            }
            var shown = fitting.slice(0, MAX_PRODUCTS);
            var sugg = chips([addChip(shown[0]), priceChip(shown[0]), stockChip(query), OFFERS_CHIP]);
            var text = max == null
              ? (exact ? 'The cheapest ' + query + ' right now:' : 'The cheapest of what I found for "' + query + '":')
              : (exact ? cap(query) + ' under ' + formatMoney(max) + ':'
                : 'What I found for "' + query + '" under ' + formatMoney(max) + ':');
            return { text: text, products: shown, links: [link], suggestions: sugg, _chipProducts: chipsFor(sugg, shown[0]) };
          });
        },

        price: function () {
          var query = intent.query;
          if (!query) {
            return { text: 'Tell me which product, for example "How much is avocado?".',
              suggestions: ['Cheapest avocado', OFFERS_CHIP, CATEGORIES_CHIP] };
          }
          var load = target ? fresh(target).then(function (p) { return [p]; }) : find(query, MAX_PRODUCTS);
          return load.then(function (results) {
            if (!results.length) return notFound(query);
            var p = results[0];
            var text;
            if (p.priceFils == null) {
              text = p.title + ' has no price in the store right now.';
            } else {
              text = p.title + ' is ' + formatMoney(p.priceFils) +
                (onSale(p) ? ', down from ' + formatMoney(p.compareAtFils) : '') + '.' +
                (p.available ? '' : ' It is sold out right now.');
            }
            var sugg = chips([p.available ? addChip(p) : null, stockChip(query), cheapestChip(query), OFFERS_CHIP]);
            return { text: text, products: results.slice(0, MAX_PRODUCTS), links: [searchLink(query)], suggestions: sugg,
              _chipProducts: chipsFor(sugg, p) };
          });
        },

        stock: function () {
          var query = intent.query;
          if (!query) {
            return { text: 'Tell me which product, for example "Is avocado in stock?".',
              suggestions: ['Cheapest avocado', OFFERS_CHIP, CATEGORIES_CHIP] };
          }
          return find(query, MAX_PRODUCTS).then(function (results) {
            if (!results.length) return notFound(query);
            var p = results[0], text;
            if (p.available) {
              text = 'Yes, ' + p.title + ' is in stock.';
            } else {
              var other = firstAvailable(results.slice(1));
              text = p.title + ' is sold out right now.' + (other ? ' ' + other.title + ' is in stock.' : '');
            }
            var sugg = p.available ? chips([addChip(p), priceChip(p), cheapestChip(query)])
              : chips([cheapestChip(query), OFFERS_CHIP, CATEGORIES_CHIP]);
            return { text: text, products: results.slice(0, MAX_PRODUCTS), links: [searchLink(query)], suggestions: sugg,
              _chipProducts: chipsFor(sugg, p) };
          });
        },

        recipe: function () {
          var r = intent.recipe;
          var found = new Array(r.ingredients.length), next = 0;
          function worker() {
            if (next >= r.ingredients.length) return Promise.resolve();
            var index = next++;
            var ing = r.ingredients[index];
            return find(ing, 10).then(function (res) {
              found[index] = cheapestAvailable(res.filter(function (p) { return titleHas(p.title, ing); }));
              return worker();
            });
          }
          var workers = [];
          for (var w = 0; w < RECIPE_SEARCH_WIDTH && w < r.ingredients.length; w++) workers.push(worker());
          return Promise.all(workers).then(function () {
            var products = [], missing = [];
            found.forEach(function (p, i) {
              if (!p) missing.push(r.ingredients[i]);
              else if (!any(products, function (x) { return x.id === p.id; })) products.push(p);
            });
            var others = otherRecipes(r);
            if (!products.length) {
              return {
                text: 'I could not find the ingredients for ' + r.dish + ' in stock right now.',
                suggestions: [others[0].message, others[1].message, others[2].message, OFFERS_CHIP, CATEGORIES_CHIP]
              };
            }
            var shown = products.slice(0, MAX_RECIPE_PRODUCTS);
            var sugg = chips([ADD_ALL_CHIP, addChip(shown[0]), others[0].message, others[1].message, CART_CHIP]);
            return {
              text: missing.length ? 'For ' + r.dish + ', you could use these. I could not find ' + joinAnd(missing) +
                ' in stock right now.' : 'For ' + r.dish + ', you could use:',
              products: shown, suggestions: sugg, _chipProducts: chipsFor(sugg, shown[0]), _addAll: shown
            };
          });
        },

        recipeIdeas: function () {
          return {
            text: 'Here are some ideas. Pick one and I will find what you need in the store.',
            suggestions: RECIPES.map(function (x) { return x.message; })
          };
        },

        favourites: function () {
          return {
            text: 'Favourites are kept in the ' + storeName + ' app: tap the heart on a product there to save it. ' +
              'On the website, your account has your orders and details.',
            links: [{ label: 'My account', url: '/account' }],
            suggestions: [POPULAR_CHIP, CATEGORIES_CHIP, OFFERS_CHIP]
          };
        },

        contact: function () {
          return { text: contactText, links: contactLinks, suggestions: [DELIVERY_CHIP, PAYMENT_CHIP, OFFERS_CHIP] };
        },

        payment: function () {
          var text = 'The website takes Visa, Mastercard and Apple Pay at checkout. Orders in the ' + storeName +
            ' app are cash on delivery: you pay the driver when your order arrives.';
          return readCart().then(function (cart) {
            return cart.items.length
              ? { text: text, links: [CART_LINK], suggestions: [DELIVERY_CHIP, CART_CHIP, CONTACT_CHIP] }
              : { text: text, suggestions: [DELIVERY_CHIP, OFFERS_CHIP, CONTACT_CHIP] };
          }, function () { return { text: text, suggestions: [DELIVERY_CHIP, OFFERS_CHIP, CONTACT_CHIP] }; });
        },

        delivery: function () {
          return delivery().then(function (d) {
            if (!d.area) {
              return {
                text: storeName + ' delivers across the seven emirates of the UAE. ' + CHOOSE_AREA + ' and I will show ' +
                  'when your order arrives and whether Express reaches you.',
                suggestions: [EXPRESS_Q_CHIP, PAYMENT_CHIP, CONTACT_CHIP]
              };
            }
            var express;
            if (d.expressAvailableHere === false) express = 'not available in your area';
            else if (d.expressOpen === false) express = 'closed right now (it runs ' + EXPRESS_HOURS + ')';
            else if (d.promiseExpress) express = lowerFirst(String(d.promiseExpress).replace(/[.\s]+$/, '')) +
              ' for items marked Express';
            else express = 'open now for items marked Express';
            var market = d.promiseMarket ? ': ' + String(d.promiseMarket).replace(/[.\s]+$/, '') : '';
            return {
              text: 'Delivering to ' + areaLabel(d) + market + '. Express: ' + express + '. ' + FEES_TEXT,
              links: d.expressAvailableHere === false ? [] : [EXPRESS_LINK],
              suggestions: [EXPRESS_Q_CHIP, PAYMENT_CHIP, CART_CHIP]
            };
          });
        },

        express: function () {
          return delivery().then(function (d) {
            if (!d.area) {
              return {
                text: 'Express brings items marked Express in under an hour, within 20 km of our Ras Al Khor hub, from ' +
                  EXPRESS_HOURS + '. ' + CHOOSE_AREA + ' to check Express.',
                links: [EXPRESS_LINK], suggestions: [DELIVERY_CHIP, EXPRESS_CHIP, CART_CHIP]
              };
            }
            var market = d.promiseMarket ? ' ' + storeName + ' delivers ' +
              lowerFirst(String(d.promiseMarket).replace(/[.\s]+$/, '')) + '.' : '';
            if (d.expressAvailableHere === false) {
              return { text: "Express isn't available in " + d.area + ' yet.' + market,
                suggestions: [DELIVERY_CHIP, OFFERS_CHIP, CART_CHIP] };
            }
            var text = d.expressOpen === false
              ? 'Express is closed right now. It runs ' + EXPRESS_HOURS + '.' + market
              : 'Express reaches ' + areaLabel(d) + ' for items marked Express. It is open until ' + EXPRESS_CLOSE + '.' +
              (d.promiseExpress ? ' ' + sentence(d.promiseExpress) : '');
            return { text: text, links: [EXPRESS_LINK], suggestions: [DELIVERY_CHIP, EXPRESS_CHIP, CART_CHIP] };
          });
        },

        help: function () {
          return { text: intent.greeting ? 'Hello! ' + OPTIONS_TEXT : OPTIONS_TEXT, showOptions: true };
        },

        thanks: function () {
          return {
            text: intent.farewell ? 'Thank you for shopping with ' + storeName + '. Come back any time.'
              : 'You are welcome. Is there anything else I can help with?',
            suggestions: [OFFERS_CHIP, CART_CHIP, CATEGORIES_CHIP]
          };
        }
      };
      handlers.category = handlers.collection;
      return Promise.resolve().then(function () { return handlers[intent.type](); });
    }

    function expressNote(d) {
      if (!d.area) return null;
      if (d.expressAvailableHere === false) return "Express isn't available in " + d.area + ' yet.';
      if (d.expressOpen === false) return 'Express is closed right now. It runs ' + EXPRESS_HOURS + '.';
      return d.promiseExpress ? sentence('Express to ' + d.area + ': ' + String(d.promiseExpress).replace(/[.\s]+$/, ''))
        : null;
    }

    function answer(intent, target) {
      var ctx = { wrote: false };
      return run(intent, target, ctx).catch(function (e) {
        if (!e || e.status !== 429 || ctx.wrote) throw e;
        return wait(retryDelay).then(function () { return run(intent, target, { wrote: false }); });
      });
    }

    function answerClear(pending, yes) {
      if (!yes) {
        return { text: 'OK, I left your cart as it is.', links: [CART_LINK], suggestions: [CART_CHIP, CHECKOUT_CHIP, OFFERS_CHIP] };
      }
      return Promise.resolve(store.cart()).then(function (cart) {
        cart = cart || { items: [] };
        var items = cart.items || [];
        if (!items.length) return { text: 'Your cart is already empty.', suggestions: START_CHIPS };
        if (!sameCart(snapshot(cart), pending)) {
          return {
            text: 'Your cart changed since you asked, so I left it as it is. Ask "Empty my cart" again if you still ' +
              'want it empty.',
            suggestions: [EMPTY_CART_CHIP, CART_CHIP, CHECKOUT_CHIP]
          };
        }
        return Promise.resolve(store.clear()).then(function (res) {
          if (res && res.ok === false) {
            return { text: 'I could not empty your cart. Please try again from the cart page.', links: [CART_LINK],
              suggestions: [CART_CHIP, CHECKOUT_CHIP, OFFERS_CHIP] };
          }
          return { text: 'Done. Your cart is empty now.', cartChanged: true, suggestions: START_CHIPS };
        });
      });
    }

    function addAll(products) {
      var added = [], soldOut = [], failed = [];
      return products.reduce(function (p, product) {
        return p.then(function () {
          if (!product.available) { soldOut.push(product.title); return null; }
          return Promise.resolve(store.add(product.variantId, 1)).then(function (res) {
            (res && res.ok ? added : failed).push(product.title);
          }, function () { failed.push(product.title); });
        });
      }, Promise.resolve()).then(function () {
        var n = added.length;
        var text = n === 0 ? 'Nothing was added.'
          : 'Added ' + n + ' ' + (n === 1 ? 'product' : 'products') + ' to your cart: ' + joinAnd(added) + '.';
        if (soldOut.length) text += ' ' + joinAnd(soldOut) + ' ' + (soldOut.length === 1 ? 'is' : 'are') + ' sold out.';
        if (failed.length) text += ' I could not add ' + joinAnd(failed) + '.';
        return n === 0 ? { text: text }
          : { text: text, links: [CART_LINK], cartChanged: true, suggestions: [CART_CHIP, CHECKOUT_CHIP, 'Ideas for a smoothie'] };
      });
    }

    function errorReply(e) {
      if (e && typeof e.userMessage === 'string' && e.userMessage) return { text: e.userMessage };
      var network = e && (e.network === true || e.name === 'NetworkError' ||
        (e.name === 'TypeError' && /fetch|network|load failed/i.test(e.message || '')));
      return { text: network ? NETWORK_ERROR : UNEXPECTED_ERROR };
    }

    function finish(r) {
      var out = { text: r.text };
      if (r.products && r.products.length) out.products = r.products.map(publicProduct);
      if (r.links && r.links.length) out.links = r.links.slice();
      out.suggestions = r.suggestions && r.suggestions.length ? r.suggestions.slice() : DEFAULT_SUGGESTIONS.slice();
      if (r.showOptions) out.showOptions = true;
      if (r.cartChanged) out.cartChanged = true;
      if (r.navigate) out.navigate = r.navigate;
      last = { clear: r._clear || null, chipProducts: r._chipProducts || {}, addAll: r._addAll || null };
      return out;
    }

    function reply(input) {
      input = input || {};
      var message;
      if (input.option != null) {
        var opt = QUICK_OPTIONS.filter(function (o) { return o.id === input.option; })[0];
        if (!opt) return Promise.resolve(finish({ text: OPTIONS_TEXT, showOptions: true }));
        message = opt.message;
      } else {
        message = String(input.chip != null ? input.chip : input.text != null ? input.text : '').trim();
      }
      var prev = last;
      return Promise.resolve().then(function () {
        if (prev.clear) {
          var yes = confirmation(message);
          if (yes !== null) return answerClear(prev.clear, yes);
        }
        if (words(message).join(' ') === 'add all to cart') {
          return prev.addAll ? addAll(prev.addAll)
            : { text: 'Tell me what to add, for example "Add 2 cucumbers".', suggestions: START_CHIPS };
        }
        var target = prev.chipProducts && Object.prototype.hasOwnProperty.call(prev.chipProducts, message)
          ? prev.chipProducts[message] : null;
        return answer(parse(message), target);
      }).catch(errorReply).then(finish, function () { return finish({ text: UNEXPECTED_ERROR }); });
    }

    return {
      reply: reply,
      /** The first message: the greeting with the options grid. */
      greeting: function () {
        return { text: greetingText, showOptions: true, suggestions: DEFAULT_SUGGESTIONS.slice() };
      },
      /** Forget the conversation (a pending "Are you sure?", chip products). */
      reset: function () { last = {}; }
    };
  }

  function qtyIn(cart, variantId) {
    var n = 0;
    cart.items.forEach(function (l) { if (String(l.variantId) === String(variantId)) n += l.quantity; });
    return n;
  }
  function snapshot(cart) {
    var map = {};
    (cart.items || []).forEach(function (l) { map[String(l.variantId)] = (map[String(l.variantId)] || 0) + l.quantity; });
    return map;
  }
  function sameCart(a, b) {
    var ka = Object.keys(a), kb = Object.keys(b);
    return ka.length === kb.length && all(ka, function (k) { return b[k] === a[k]; });
  }

  var FMAskBrain = {
    create: create,
    parse: parse,
    confirmation: confirmation,
    words: words,
    singular: singular,
    isPlainWord: isPlainWord,
    shortName: shortName,
    formatMoney: formatMoney,
    QUICK_OPTIONS: QUICK_OPTIONS,
    DEFAULT_SUGGESTIONS: DEFAULT_SUGGESTIONS,
    RECIPES: RECIPES,
    CATEGORIES: CATEGORIES,
    COLLECTIONS: COLLECTIONS
  };
  if (root) root.FMAskBrain = FMAskBrain;
  if (typeof module !== 'undefined' && module.exports) module.exports = FMAskBrain;
})(typeof window !== 'undefined' ? window : null);
