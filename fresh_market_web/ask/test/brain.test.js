// Node tests for fm-ask-brain.js, ported from the app's
// test/assistant_intent_test.dart and test/assistant_brain_test.dart.
// Run: node --test fresh_market_web/ask/test/
// All products, prices and areas below are fictional demo data.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const B = require('../assets/fm-ask-brain.js');

const money = B.formatMoney;

// ---- fake store -------------------------------------------------------------

function item(id, title, fils, o = {}) {
  return {
    id, variantId: id + 5000, handle: 'p' + id, title, subtitle: o.subtitle || '', priceFils: fils,
    compareAtFils: o.compareAt == null ? null : o.compareAt, available: o.available !== false, image: '',
    url: '/products/p' + id, tags: o.tags || [], vendor: o.vendor || ''
  };
}

/** Demo shelf: search matches title substrings ("banana" finds "Bananarama Bread"). */
function shelf() {
  return [
    item(100, 'Strawberry', 1800, { compareAt: 2400 }),
    item(101, 'Zespri Kiwi Sungold', 1200),
    item(102, 'Cucumber', 350),
    item(103, 'Blueberry', 1600, { available: false }),
    item(104, 'Demo Beef Cubes', 3250, { compareAt: 6000 }),
    item(1, 'Bananarama Bread', 900),
    item(2, 'Banana Chiquita', 650),
    item(3, 'Organic Blueberry Punnet', 2400),
    item(4, 'Mango Alphonso', 3000),
    item(5, 'Avocado Hass', 1250),
    item(6, 'Avocado Shepard', 800),
    item(7, 'Avocado Organic', 2000),
    item(8, 'Avocado Fuerte', 500, { available: false }),
    item(9, 'Avocado Mini', 800),
    item(10, 'Tomatoes Cherry', 450),
    item(11, 'Red Onions', 300)
  ];
}

function fakeStore(o = {}) {
  const products = o.products || shelf();
  const collections = o.collections || { 'fresh-meat': [products[4]], 'best-deals': [products[0], products[4]],
    berries: [products[0], products[3], products[2]] };
  const lines = [];
  let inFlight = 0;
  const s = {
    calls: [], maxInFlight: 0, error: null, delivery_: o.delivery || null, maxPerLine: o.maxPerLine || 99,
    async search(q, limit) {
      s.calls.push(`search(${q},${limit})`);
      if (s.error) throw s.error;
      inFlight++; s.maxInFlight = Math.max(s.maxInFlight, inFlight);
      await new Promise((r) => setTimeout(r, 1));
      inFlight--;
      return products.filter((p) => p.title.toLowerCase().includes(q.toLowerCase())).slice(0, limit);
    },
    async collection(h, limit) {
      s.calls.push(`collection(${h})`);
      if (s.error) throw s.error;
      if (!collections[h]) { const e = new Error('Not found'); e.status = 404; throw e; }
      return collections[h].slice(0, limit);
    },
    async collections() { return Object.keys(collections).map((h) => ({ handle: h, title: h })); },
    async product(h) { s.calls.push(`product(${h})`); return products.find((p) => p.handle === h) || null; },
    async cart() {
      return {
        items: lines.map((l) => ({ key: l.key, variantId: l.variantId, title: l.title, quantity: l.quantity,
          lineFils: l.quantity * l.price })),
        itemCount: lines.reduce((n, l) => n + l.quantity, 0),
        totalFils: lines.reduce((n, l) => n + l.quantity * l.price, 0)
      };
    },
    async add(variantId, quantity) {
      s.calls.push(`add(${variantId},${quantity})`);
      const p = products.find((x) => x.variantId === variantId);
      if (!p || !p.available) return { ok: false, error: 'This item is sold out' };
      let l = lines.find((x) => x.variantId === variantId);
      if (!l) { l = { key: variantId + ':k', variantId, title: p.title, quantity: 0, price: p.priceFils }; lines.push(l); }
      if (l.quantity >= s.maxPerLine) return { ok: false, error: `All ${s.maxPerLine} are in your cart` };
      l.quantity = Math.min(s.maxPerLine, l.quantity + quantity);
      return { ok: true };
    },
    async setQuantity(key, q) {
      s.calls.push(`setQuantity(${key},${q})`);
      const i = lines.findIndex((l) => l.key === key);
      if (i < 0) return { ok: false, error: 'No such line' };
      if (q <= 0) lines.splice(i, 1); else lines[i].quantity = q;
      return { ok: true };
    },
    async clear() { s.calls.push('clear'); lines.length = 0; return { ok: true }; },
    async delivery() {
      return s.delivery_ || { area: null, emirate: null, mode: null, expressOpen: null, expressAvailableHere: null,
        promiseMarket: null, promiseExpress: null };
    },
    qty(variantId) { const l = lines.find((x) => x.variantId === variantId); return l ? l.quantity : 0; },
    lines
  };
  return s;
}

const config = { contactPhone: '800 0 000000', contactEmail: 'care@example.test', storeName: 'Fresh Market',
  greeting: 'Hi! Demo greeting.', retryDelayMs: 1 };
function setup(o) { const store = fakeStore(o); return { store, brain: B.create(store, config) }; }
const say = (brain, text) => brain.reply({ text });

// ---- intent tables (assistant_intent_test.dart) -----------------------------

function describe(i) {
  switch (i.type) {
    case 'add': return `Add(${i.quantity}, ${i.query})`;
    case 'remove': return `Remove(${i.quantity == null ? 'all' : i.quantity}, ${i.query})`;
    case 'clearCart': return 'ClearCart';
    case 'checkout': return 'Checkout';
    case 'cart': return 'Cart';
    case 'offers': return 'Offers';
    case 'category': return `Category(${i.handle})`;
    case 'collection': return `Collection(${i.handle})`;
    case 'allCategories': return 'AllCategories';
    case 'cheapest': return i.maxFils == null ? `Cheapest(${i.query})` : `Cheapest(${i.query}, ${i.maxFils})`;
    case 'price': return `Price(${i.query})`;
    case 'stock': return `Stock(${i.query})`;
    case 'recipe': return `Recipe(${i.recipe.name})`;
    case 'recipeIdeas': return 'RecipeIdeas';
    case 'favourites': return 'Favourites';
    case 'contact': return 'Contact';
    case 'payment': return 'Payment';
    case 'delivery': return 'Delivery';
    case 'express': return 'Express';
    case 'brands': return 'Brands';
    case 'help': return i.greeting ? 'Greeting' : 'Help';
    case 'thanks': return i.farewell ? 'Bye' : 'Thanks';
    case 'search': return `Search(${i.query})`;
  }
  return '?';
}
const d = (t) => describe(B.parse(t));
function table(rows) { for (const [text, want] of rows) assert.equal(d(text), want, text); }

test('words are lower-cased, punctuation dropped, apostrophes join', () => {
  assert.deepEqual(B.words("What's  ON offer?!"), ['whats', 'on', 'offer']);
  assert.deepEqual(B.words(''), []);
});

test('add: quantities, filler, caps, second items, weights', () => {
  table([
    ['Add 2 cucumbers', 'Add(2, cucumbers)'], ['add three kiwi', 'Add(3, kiwi)'], ['Buy strawberry', 'Add(1, strawberry)'],
    ['add ten Blueberry', 'Add(10, blueberry)'], ['add 500 lemons', 'Add(20, lemons)'], ['add 0 lemons', 'Add(1, lemons)'],
    ['Please add 2 cucumbers to my cart!', 'Add(2, cucumbers)'], ['Please buy some beef cubes', 'Add(1, beef cubes)'],
    ['I want to add 2 kiwi', 'Add(2, kiwi)'], ['can you add a kiwi to the basket', 'Add(1, kiwi)'],
    ['add 2 seven up', 'Add(2, seven up)'], ['add', 'Add(1, )'], ['add to cart', 'Add(1, )'],
    ['add berries to cart', 'Add(1, berries)'], ['add 2 checkout bags', 'Add(2, checkout bags)'],
    ['Where can I buy strawberries?', 'Search(strawberries)'], ["Don't add onions", 'Search(onions)'],
    ['do not add onions', 'Search(onions)'], ['I want to buy some apples', 'Search(apples)'],
    ['How do I add a kiwi?', 'Search(kiwi)'], ['Where can I buy berries?', 'Category(berries)'],
    ['Buy 1 get 1 free offers', 'Offers'], ['buy 2 deals', 'Offers'], ['buy one get one free', 'Offers'],
    ['Add 3x bananas', 'Add(3, bananas)'], ['add bananas x3', 'Add(3, bananas)'], ['add a dozen eggs', 'Add(12, eggs)'],
    ['Put 2 cucumbers in my cart', 'Add(2, cucumbers)'], ['get me a kiwi in my basket', 'Add(1, kiwi)'],
    ['order 2 cucumbers', 'Add(2, cucumbers)'], ['please order a kiwi', 'Add(1, kiwi)'],
    ['add twenty limes', 'Add(20, limes)'], ['add fifteen kiwis', 'Add(15, kiwis)'],
    ['add eleven cucumbers', 'Add(11, cucumbers)'], ['thanks, add 2 cucumbers', 'Add(2, cucumbers)'],
    ['pls add 2 kiwis', 'Add(2, kiwis)'], ['add dates', 'Add(1, dates)'], ['buy in bulk', 'Collection(bulk-buy)'],
    ['add gluten free bread', 'Add(1, gluten free bread)']
  ]);
  for (const [text, more] of [['Add 2 apples and 3 bananas', true], ['add 2 apples, 3 bananas', true],
    ['add apples and some bananas', true], ['add 2 cucumbers and show me offers', true],
    ['add 2 cucumbers to my cart and checkout', true], ['add 2 cucumbers', false]]) {
    const i = B.parse(text);
    assert.equal(i.moreItems, more, text);
    assert.match(i.query, /^(apples|cucumbers)$/, text);
  }
  for (const [text, q] of [['add 1.5 kg potatoes', 'potatoes'], ['add 2kg tomatoes', 'tomatoes'],
    ['Add half a kilo of tomatoes', 'tomatoes'], ['add 500 g cherries', 'cherries']]) {
    const i = B.parse(text);
    assert.equal(i.type, 'add', text);
    assert.equal(i.measureAsked, true, text);
    assert.equal(i.quantity, 1, text);
    assert.equal(i.query, q, text);
  }
});

test('remove, empty, checkout, cart, offers', () => {
  table([
    ['Remove cucumbers from my cart', 'Remove(all, cucumbers)'], ['delete kiwi', 'Remove(all, kiwi)'],
    ['take the kiwi out of my cart', 'Remove(all, kiwi)'], ['remove 1 cucumber', 'Remove(1, cucumber)'],
    ['Delete the bananas from my cart', 'Remove(all, bananas)'], ['take the berries out of my cart', 'Remove(all, berries)'],
    ['remove two kiwis', 'Remove(2, kiwis)'], ['remove a kiwi', 'Remove(1, kiwi)'],
    ['get rid of the onions', 'Remove(all, onions)'], ['remove the 1 kg strawberries', 'Remove(all, strawberries)'],
    ['remove all cucumbers', 'Remove(all, cucumbers)'], ['Remove clear honey', 'Remove(all, clear honey)'],
    ['remove', 'Remove(all, )'], ['remove kiwi from my favourites', 'Favourites'], ['remove twelve kiwis', 'Remove(12, kiwis)'],
    ['empty my cart', 'ClearCart'], ['Clear my cart', 'ClearCart'], ['remove everything', 'ClearCart'],
    ['delete all items from my basket', 'ClearCart'], ['take everything out of my cart', 'ClearCart'],
    ['please empty the basket', 'ClearCart'], ['clear the basket', 'ClearCart'], ['is my cart empty?', 'Cart'],
    ['Checkout', 'Checkout'], ['I want to pay', 'Checkout'], ['check out', 'Checkout'], ['Pay now', 'Checkout'],
    ['checkout my cart', 'Checkout'], ['Open my cart', 'Cart'], ["what's in my basket?", 'Cart'], ['CART', 'Cart'],
    ['basket', 'Cart'], ['show basket', 'Cart'], ['add a kiwi to a basket', 'Add(1, kiwi)'],
    ['fruit basket', 'Search(fruit basket)'], ['gift basket', 'Search(gift basket)'],
    ['add a fruit basket', 'Add(1, fruit basket)'], ['get a fruit basket', 'Search(fruit basket)'],
    ['remove the fruit basket', 'Remove(all, fruit basket)'],
    ['take the fruit basket out of my basket', 'Remove(all, fruit basket)'],
    ['What is on offer?', 'Offers'], ['offers', 'Offers'], ['any deals today', 'Offers'], ['Best deal', 'Offers'],
    ['what is on sale', 'Offers'], ['discount', 'Offers'], ['show me discounts', 'Offers'], ['meat offers', 'Offers']
  ]);
});

test('categories, collections and searches', () => {
  const cats = { fruit: 'fruits', Fruits: 'fruits', vegetable: 'vegetables', veg: 'vegetables', veggies: 'vegetables',
    meat: 'fresh-meat', butchery: 'fresh-meat', berries: 'berries', flowers: 'ambrosia-flowers', hamper: 'hampers',
    gifts: 'hampers', citrus: 'citrus', oranges: 'citrus', lemon: 'citrus', mango: 'mangoes', mangos: 'mangoes',
    melon: 'melons-pineapples', pineapple: 'melons-pineapples', tropical: 'tropical-exotic', exotic: 'tropical-exotic',
    greens: 'lettuce-greens', lettuce: 'lettuce-greens', salad: 'lettuce-greens', herb: 'fresh-herbs', herbs: 'fresh-herbs' };
  for (const [w, h] of Object.entries(cats)) assert.equal(d(w), `Category(${h})`, w);
  table([
    ['Show me berries', 'Category(berries)'], ['Do you have any flowers?', 'Category(ambrosia-flowers)'],
    ['open the fresh meat section', 'Category(fresh-meat)'], ['exotic fruits', 'Category(tropical-exotic)'],
    ['orange juice', 'Search(orange juice)'], ['strawberries', 'Search(strawberries)'],
    ['Find avocado', 'Search(avocado)'], ['Do you have any Zespri kiwi, please?', 'Search(zespri kiwi)'],
    ['I need some lamb chops', 'Search(lamb chops)'], ['', 'Search()'], ['please', 'Search()'], ['show me', 'Search()'],
    ['Show local UAE produce', 'Collection(local-uae)'], ['anything made in UAE', 'Collection(local-uae)'],
    ['emirati products', 'Collection(local-uae)'], ['organic food', 'Collection(organic-food)'],
    ["What's new?", 'Collection(new-arrivals)'], ['new arrivals', 'Collection(new-arrivals)'],
    ['latest products', 'Collection(new-arrivals)'], ['What is popular?', 'Collection(best-sellers)'],
    ['best sellers', 'Collection(best-sellers)'], ['what do you recommend', 'Collection(best-sellers)'],
    ['top', 'Collection(best-sellers)'], ['trending', 'Collection(trending)'],
    ['1hr express products', 'Collection(express)'], ['one hour', 'Collection(express)'],
    ['I need it urgent', 'Collection(express)'], ['wholesale', 'Collection(bulk-buy)'], ['milk', 'Collection(dairy)'],
    ['eggs', 'Collection(eggs-cheese)'], ['dates', 'Collection(dates)'], ['dried fruits', 'Collection(nuts-dried-fruits)'],
    ['healthy snacks', 'Collection(healthy-pouches)'], ['fruit platter', 'Collection(ambrosia-platters)'],
    ['party platters', 'Collection(ambrosia-platters)'], ['fruit bouquet', 'Collection(ambrosia-bouquets)'],
    ['birthday gift', 'Collection(ambrosia-occasions)'], ['wedding flowers', 'Collection(ambrosia-occasions)'],
    ['Eid gifts', 'Collection(ambrosia-eid)'], ['iftar', 'Collection(ambrosia-ramadan)'],
    ['christmas hamper', 'Collection(ambrosia-christmas)'], ["Valentine's Day", 'Collection(ambrosia-valentines)'],
    ["mother's day", 'Collection(ambrosia-mothers-day)'], ['something for my mum', 'Collection(ambrosia-mothers-day)'],
    ["women's day", 'Collection(ambrosia-mothers-day)'], ['flower bouquet', 'Category(ambrosia-flowers)'],
    ['Gift ideas', 'Category(hampers)'], ['new zealand kiwi', 'Search(new zealand kiwi)'],
    ['low fat milk', 'Search(low fat milk)'], ['milk chocolate', 'Search(milk chocolate)'],
    ['categories', 'AllCategories'], ['Show all categories', 'AllCategories'], ['What do you sell?', 'AllCategories'],
    ['browse', 'AllCategories'], ['departments', 'AllCategories'], ['what do you have', 'AllCategories'],
    ['fruit categories', 'Category(fruits)'], ['browse fruits', 'Category(fruits)'],
    ['brands', 'Brands'], ['brands you have', 'Brands'], ['which brands do you stock', 'Brands'],
    ['Zespri', 'Search(zespri)'], ['zespri brand', 'Search(zespri)'], ['Find Zespri', 'Search(zespri)']
  ]);
  // Every collection is reachable by a word.
  const reached = new Set(B.COLLECTIONS.map((c) => c.handle).filter((h) => d(h.split('-')[0]) !== ''));
  assert.equal(reached.size, B.COLLECTIONS.length);
});

test('cheapest, price, stock', () => {
  table([
    ['Cheapest avocado', 'Cheapest(avocado)'], ['cheap berries', 'Cheapest(berries)'],
    ['avocado under 20', 'Cheapest(avocado, 2000)'], ['strawberries below 30 dhs', 'Cheapest(strawberries, 3000)'],
    ['kiwi less than 15 aed', 'Cheapest(kiwi, 1500)'], ['budget mango', 'Cheapest(mango)'],
    ['blueberries under AED 12.50', 'Cheapest(blueberries, 1250)'], ['lettuce for 10 dhs or less', 'Cheapest(lettuce, 1000)'],
    ['mango under 15 dirhams', 'Cheapest(mango, 1500)'], ['the least expensive dates', 'Cheapest(dates)'],
    ['cheapest', 'Cheapest()'], ['something under 20', 'Cheapest(, 2000)'], ['cheap deals', 'Offers'],
    ['How much is avocado?', 'Price(avocado)'], ['price of kiwi', 'Price(kiwi)'],
    ['What does a cucumber cost?', 'Price(cucumber)'], ['how much are the strawberries', 'Price(strawberries)'],
    ['avocado price', 'Price(avocado)'], ['how much is 1 kg avocado', 'Price(avocado)'], ['how much', 'Price()'],
    ['how much is my cart', 'Cart'], ['how much is delivery', 'Delivery'],
    ['Is avocado available?', 'Stock(avocado)'], ['do you have kiwi in stock', 'Stock(kiwi)'],
    ['blueberry in stock?', 'Stock(blueberry)'], ['are the blueberries sold out', 'Stock(blueberries)'],
    ['When will raspberries be back in stock?', 'Stock(raspberries)'], ['do you have kiwi', 'Search(kiwi)']
  ]);
});

test('recipes', () => {
  table([
    ['Ideas for a fruit salad', 'Recipe(fruit salad)'], ['smoothie recipe', 'Recipe(smoothie)'],
    ['salad ideas', 'Recipe(green salad)'], ['green salad recipe', 'Recipe(green salad)'],
    ['how to make guacamole', 'Recipe(guacamole)'], ['something for a BBQ', 'Recipe(BBQ)'],
    ['what can I cook on the grill', 'Recipe(BBQ)'], ['What can I make for breakfast?', 'Recipe(breakfast)'],
    ['what can I make with avocado', 'Recipe(guacamole)'], ['add everything for a smoothie', 'Recipe(smoothie)'],
    ['recipe ideas', 'RecipeIdeas'], ['ideas', 'RecipeIdeas'], ['what should I cook tonight', 'RecipeIdeas'],
    ['cooking oil', 'Search(cooking oil)'], ['ideas for a party', 'Collection(ambrosia-occasions)']
  ]);
  assert.deepEqual(B.RECIPES.map((r) => r.message), ['Ideas for a fruit salad', 'Ideas for a smoothie',
    'Ideas for a green salad', 'Ideas for guacamole', 'Ideas for a BBQ', 'Ideas for breakfast']);
  for (const r of B.RECIPES) assert.equal(d(r.message), `Recipe(${r.name})`);
  assert.equal(B.RECIPES[0].label, 'Fruit salad ideas');
});

test('store information, small talk, Gulf courtesy words', () => {
  table([
    ['hi', 'Greeting'], ['Hello there!', 'Greeting'], ['Good morning', 'Greeting'], ['help', 'Help'],
    ['I need help', 'Help'], ['What can you do?', 'Help'], ['Show me the menu', 'Help'], ['how does this work', 'Help'],
    ['hi, show me berries', 'Category(berries)'], ['help me find avocado', 'Search(avocado)'],
    ['thanks', 'Thanks'], ['Thank you so much!', 'Thanks'], ['no thanks', 'Thanks'], ['bye', 'Bye'],
    ['ok bye, see you later', 'Bye'], ['my favourites', 'Favourites'], ['saved items', 'Favourites'],
    ['my wish list', 'Favourites'], ['my list', 'Favourites'], ['add kiwi to my favourites', 'Favourites'],
    ['Contact customer service', 'Contact'], ['what is your phone number', 'Contact'], ['can I call you', 'Contact'],
    ['I have a complaint', 'Contact'], ['support', 'Contact'], ['opening hours', 'Contact'],
    ['where are you located', 'Contact'], ['when do you open', 'Contact'], ['my order is late', 'Contact'],
    ['track my order', 'Contact'], ["my order hasn't arrived", 'Contact'], ['order status', 'Contact'],
    ['where is my order?', 'Contact'], ['where is my delivery', 'Contact'],
    ["when will my order arrive? it hasn't come", 'Contact'], ['where do you have berries', 'Category(berries)'],
    ['payment methods', 'Payment'], ['How can I pay?', 'Payment'], ['cash on delivery', 'Payment'],
    ['do you take apple pay', 'Payment'], ['pay by card', 'Payment'], ['do you accept credit cards', 'Payment'],
    ['pay', 'Checkout'], ['how much do I have to pay', 'Checkout'], ['gift card', 'Search(gift card)'],
    ['delivery', 'Delivery'], ['do you deliver to Abu Dhabi?', 'Delivery'], ['when will it arrive', 'Delivery'],
    ['delivery fee', 'Delivery'], ['change my address', 'Delivery'], ['is there a minimum order', 'Delivery'],
    ['When will my order arrive?', 'Delivery'], ['when will my order be delivered', 'Delivery'],
    ['express delivery', 'Express'], ['Is Express open?', 'Express'], ['is express available in my area', 'Express'],
    ['can I get it in 1 hour', 'Express'], ['Do you deliver in one hour?', 'Express'],
    ['what time does express close', 'Express'], ['express', 'Collection(express)'],
    ['Show 1Hr Express', 'Collection(express)'], ['how fast is delivery', 'Delivery'],
    ['shukran habibi', 'Thanks'], ['yalla bye', 'Bye'], ['khalas thanks', 'Bye'], ['salam', 'Greeting'],
    ['habibi show me mangoes', 'Category(mangoes)'], ['salam, do you have dates?', 'Collection(dates)'],
    ['wallah the cheapest avocado', 'Cheapest(avocado)'], ['do you sell chiquita bananas', 'Search(chiquita bananas)']
  ]);
});

test('confirmation, singular and plain words', () => {
  for (const t of ['yes', 'Yes please', 'yes empty it', 'ok, clear my cart', 'confirm', 'go ahead', 'do it', 'sure',
    'Yes, empty my cart']) assert.equal(B.confirmation(t), true, t);
  for (const t of ['no', 'No thanks', 'cancel', 'keep it', "don't", 'No, keep my cart']) {
    assert.equal(B.confirmation(t), false, t);
  }
  for (const t of ['', 'add 2 kiwis', 'no, add 2 kiwis', 'show me']) assert.equal(B.confirmation(t), null, t);
  assert.equal(B.singular('cucumbers'), 'cucumber');
  assert.equal(B.singular('berries'), 'berry');
  assert.equal(B.singular('mangoes'), 'mango');
  assert.equal(B.singular('lamb chops'), 'lamb chop');
  assert.equal(B.singular('citrus'), 'citrus');
  assert.equal(B.singular('watercress'), 'watercress');
  for (const w of ['kiwi', 'zespri', 'sungold', 'honey', 'basket']) assert.equal(B.isPlainWord(w), true, w);
  for (const w of ['', '500gm', '7', 'kg', 'offer', 'free', 'and', 'clear', 'cart', 'card', 'delivery', 'price',
    'stock', 'the', 'eleven', 'twenty']) assert.equal(B.isPlainWord(w), false, w);
  assert.equal(B.shortName('Zespri Kiwi Sungold 500 GM Pack'), 'Zespri Kiwi Sungold');
  assert.equal(B.shortName('Add 1 Free Offer'), null);
});

test('ready-made messages parse to what they say', () => {
  assert.deepEqual(B.DEFAULT_SUGGESTIONS.map(d), ['Offers', 'Category(berries)', 'Add(2, cucumbers)',
    'Recipe(fruit salad)', 'Cheapest(avocado)', 'Collection(local-uae)', 'Category(hampers)', 'Collection(new-arrivals)',
    'Contact', 'Cart']);
  assert.deepEqual(B.QUICK_OPTIONS.map((o) => o.id),
    ['offers', 'categories', 'recipes', 'local', 'gifts', 'bestsellers', 'cart', 'care']);
  assert.deepEqual(B.QUICK_OPTIONS.map((o) => d(o.message)), ['Offers', 'AllCategories', 'RecipeIdeas',
    'Collection(local-uae)', 'Category(hampers)', 'Collection(best-sellers)', 'Cart', 'Contact']);
});

// ---- brain replies (assistant_brain_test.dart) ----------------------------

/** Each chip parses to the request it reads as, never to a search. */
function goodChips(reply) {
  assert.ok(reply.suggestions.length >= 3 && reply.suggestions.length <= 6, reply.text);
  assert.equal(new Set(reply.suggestions).size, reply.suggestions.length);
  for (const c of reply.suggestions) {
    const i = B.parse(c);
    assert.notEqual(i.type, 'search', c);
    if (c.startsWith('Add 1 ')) { assert.equal(i.type, 'add', c); assert.equal(i.quantity, 1); assert.ok(i.query); }
    if (c.startsWith('Cheapest ')) { assert.equal(i.type, 'cheapest', c); assert.ok(i.query); }
    if (c.startsWith('How much is ')) { assert.equal(i.type, 'price', c); assert.ok(i.query); }
    if (c.startsWith('Remove ')) { assert.equal(i.type, 'remove', c); assert.ok(i.query); }
  }
}

test('add: quantity, cheapest that names it, price said, cart changed', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'Add 2 cucumbers');
  assert.equal(r.text, `Done. I added 2 × Cucumber to your cart at ${money(350)} each.`);
  assert.equal(r.cartChanged, true);
  assert.deepEqual(r.links, [{ label: 'Open cart', url: '/cart' }]);
  assert.equal(r.products[0].title, 'Cucumber');
  assert.equal(store.qty(5102), 2);
  assert.deepEqual(store.calls.filter((c) => c.startsWith('search')), ['search(cucumbers,10)', 'search(cucumber,10)']);
  goodChips(r);
  // Not the first one the store lists, nor the sold-out one.
  r = await say(brain, 'add an avocado');
  assert.equal(r.text, `Done. I added 1 × Avocado Shepard to your cart at ${money(800)}.`);
  assert.equal(store.qty(5006), 1);
  assert.equal(money(125000), 'AED 1,250.00');
});

test('add: sold out, not found, nothing named, question, weight, two items, cart limit', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'add avocado fuerte');
  assert.match(r.text, /^Avocado Fuerte is sold out right now, so nothing was added\./);
  assert.equal(r.cartChanged, undefined);
  r = await say(brain, 'add 2 dragonfruit');
  assert.match(r.text, /could not find "dragonfruit"/);
  store.calls.length = 0;
  r = await say(brain, 'add');
  assert.match(r.text, /Tell me what to add/);
  assert.deepEqual(store.calls, []);
  for (const t of ['Where can I buy cucumber?', "Don't add cucumber"]) await say(brain, t);
  assert.equal(store.lines.length, 0);
  r = await say(brain, 'add 2kg tomatoes');
  assert.match(r.text, /only add whole packs, so nothing was added/);
  assert.equal(r.products[0].title, 'Tomatoes Cherry');
  assert.equal(store.lines.length, 0);
  r = await say(brain, 'add 2 cucumbers and 3 bananas');
  assert.match(r.text, /I added 2 .* Cucumber.*I add one product per message, so ask again for the rest\.$/);
  store.maxPerLine = 2;
  r = await say(brain, 'add 1 cucumber');
  assert.equal(r.text, 'I could not add Cucumber to your cart. All 2 are in your cart.');
});

test('a product chip acts on the row it was made from', async () => {
  const box = item(30, 'Kiwi Green Zespri', 25200);
  const pack = item(31, 'Kiwi Green Zespri', 1895);
  const { store, brain } = setup({ products: [box, pack] });
  const found = await say(brain, 'find kiwi green');
  assert.equal(found.products[0].id, 30);
  assert.ok(found.suggestions.includes('Add 1 Kiwi Green Zespri'));
  store.calls.length = 0;
  let r = await brain.reply({ chip: 'Add 1 Kiwi Green Zespri' });
  assert.equal(r.text, `Done. I added 1 × Kiwi Green Zespri to your cart at ${money(25200)}.`);
  assert.equal(store.qty(5030), 1);
  assert.equal(store.qty(5031), 0);
  assert.deepEqual(store.calls.filter((c) => !c.startsWith('add')), ['product(p30)']);
  await say(brain, 'is kiwi green in stock');
  r = await brain.reply({ chip: 'How much is Kiwi Green Zespri?' });
  assert.equal(r.text, `Kiwi Green Zespri is ${money(25200)}.`);
  // Typed fresh, it searches again (and picks the cheapest that names it).
  await say(brain, 'hi');
  await say(brain, 'Add 1 Kiwi Green Zespri');
  assert.equal(store.qty(5031), 1);
});

test('remove: by number, every match, berries by ending, whole words, empty cart', async () => {
  const products = [...shelf(), item(50, 'Pineapple Gold', 1000), item(51, 'Apple Red', 500)];
  const { store, brain } = setup({ products });
  let r = await say(brain, 'remove kiwi');
  assert.equal(r.text, 'Your cart is empty, so there is nothing to remove.');
  await store.add(5102, 3); await store.add(5100, 1); await store.add(5003, 1); await store.add(5050, 1);
  await store.add(5051, 1);
  r = await say(brain, 'remove 2 cucumbers');
  assert.equal(r.text, `Removed 2 × Cucumber from your cart. Your cart has 5 items, subtotal ${money(350 + 1800 + 2400 + 1000 + 500)}.`);
  assert.equal(r.cartChanged, true);
  assert.equal(store.qty(5102), 1);
  r = await say(brain, 'remove apple');
  assert.match(r.text, /^Removed Apple Red from your cart\./);
  assert.equal(store.qty(5050), 1);
  r = await say(brain, 'take the berries out of my cart');
  assert.match(r.text, /^Removed Strawberry and Organic Blueberry Punnet from your cart\./);
  r = await say(brain, 'remove mango');
  assert.match(r.text, /^I could not find mango in your cart\./);
  r = await say(brain, 'remove');
  assert.match(r.text, /^Tell me what to remove, for example "Remove Cucumber"\./);
  goodChips(r);
  await say(brain, 'remove cucumber');
  r = await say(brain, 'remove pineapple');
  assert.equal(r.text, 'Removed Pineapple Gold from your cart. Your cart is empty now.');
});

test('empty the cart: asks first; yes empties, no keeps, a changed cart is kept', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'empty my cart');
  assert.equal(r.text, 'Your cart is already empty.');
  await store.add(5102, 2);
  r = await say(brain, 'empty my cart');
  assert.equal(r.text, 'This will remove all 2 items from your cart. Are you sure?');
  assert.deepEqual(r.suggestions.slice(0, 2), ['Yes, empty my cart', 'No, keep my cart']);
  assert.ok(!store.calls.includes('clear'));
  r = await brain.reply({ chip: 'No, keep my cart' });
  assert.equal(r.text, 'OK, I left your cart as it is.');
  assert.equal(store.qty(5102), 2);
  // Only right after the question does a yes empty it.
  r = await say(brain, 'yes');
  assert.ok(!store.calls.includes('clear'));
  r = await say(brain, 'clear the basket');
  await store.add(5100, 1);
  r = await brain.reply({ chip: 'Yes, empty my cart' });
  assert.match(r.text, /^Your cart changed since you asked/);
  assert.equal(store.lines.length, 2);
  await say(brain, 'empty my cart');
  r = await say(brain, 'yes please');
  assert.equal(r.text, 'Done. Your cart is empty now.');
  assert.equal(r.cartChanged, true);
  assert.equal(store.lines.length, 0);
});

test('checkout opens the cart; cart summary; never an order', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'checkout');
  assert.match(r.text, /^Your cart is empty, so there is nothing to check out yet/);
  assert.equal(r.navigate, undefined);
  await store.add(5102, 1);
  r = await say(brain, 'checkout');
  assert.equal(r.text, `Your cart has 1 item, subtotal ${money(350)}. Opening your cart, checkout is from there.`);
  assert.equal(r.navigate, '/cart');
  r = await brain.reply({ option: 'cart' });
  assert.equal(r.text, `Your cart has 1 item, subtotal ${money(350)}. Opening your cart.`);
  assert.equal(r.navigate, '/cart');
  goodChips(r);
  r = await say(brain, 'what is in my cart');
  assert.equal(r.text, `Your cart has 1 item, subtotal ${money(350)}.`);
  assert.equal(r.navigate, undefined);
  r = await say(brain, 'go to my basket');
  assert.equal(r.navigate, '/cart');
  assert.ok(!store.calls.some((c) => /order|checkout/.test(c)));
});

test('offers: really on sale, biggest saving first, at most three, a button per collection', async () => {
  let { brain } = setup();
  let r = await say(brain, 'What is on offer?');
  assert.deepEqual(r.products.map((p) => p.title), ['Demo Beef Cubes', 'Strawberry']);
  assert.equal(r.text, 'These are on sale today. The biggest saving is 46% on Demo Beef Cubes.');
  assert.deepEqual(r.links, [{ label: "See all Today's Top Deals", url: '/collections/fresh-meat' },
    { label: 'See all Best Deals', url: '/collections/best-deals' }]);
  goodChips(r);
  const sale = (id, old) => item(id, 'Sale ' + id, 1000, { compareAt: old });
  ({ brain } = setup({ collections: { 'fresh-meat': [sale(1, 1100), sale(2, 2000)],
    'best-deals': [sale(3, 1250), sale(4, 4000), item(5, 'Plain', 500)] } }));
  r = await brain.reply({ option: 'offers' });
  assert.deepEqual(r.products.map((p) => p.id), [4, 2, 3]);
  assert.match(r.text, /75% on Sale 4/);
  assert.deepEqual(r.links.map((l) => l.url), ['/collections/best-deals', '/collections/fresh-meat']);
  ({ brain } = setup({ collections: { 'best-deals': [item(6, 'Plain A', 500), item(7, 'Plain B', 600)] } }));
  r = await say(brain, 'deals');
  assert.equal(r.text, 'Nothing is marked down right now. Here are products from Best Deals.');
  assert.equal(r.products.length, 2);
});

test('collections and categories', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'Show me berries');
  assert.equal(r.text, 'A few products from Berries:');
  assert.equal(r.products.length, 3);
  assert.deepEqual(r.links, [{ label: 'Open Berries', url: '/collections/berries' }]);
  assert.equal(r.suggestions[0], 'Cheapest berries');
  goodChips(r);
  r = await say(brain, 'organic food');
  assert.equal(r.text, 'I could not find Organic Food in the store right now.');
  store.calls.length = 0;
  r = await brain.reply({ option: 'gifts' });
  assert.deepEqual(store.calls, ['collection(hampers)']);
  assert.match(r.text, /Hampers/);
  assert.deepEqual(r.links.map((l) => l.label), ['Open Flowers', 'Open Fruit Bouquets', 'Open Special Occasions']);
  r = await brain.reply({ option: 'categories' });
  assert.equal(r.text, 'Here are our categories.');
  // Only the tiles the store has, then the Collections page.
  assert.deepEqual(r.links.map((l) => l.url), ['/collections/fresh-meat', '/collections/berries', '/collections']);
  r = await say(brain, 'brands');
  assert.equal(r.links.length, 10);
  assert.equal(r.links[7].url, '/search?q=Thai&type=product');
});

test('search: three rows, See all results, nothing found, service words', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'Find avocado');
  assert.equal(r.text, 'Here is what I found for "avocado".');
  assert.equal(r.products.length, 3);
  assert.deepEqual(r.links, [{ label: 'See all results', url: '/search?q=avocado&type=product' }]);
  assert.deepEqual(r.suggestions, ['Cheapest avocado', 'Is avocado in stock?', 'Add 1 Avocado Hass']);
  goodChips(r);
  r = await say(brain, 'dragonfruit');
  assert.match(r.text, /^I could not find anything for "dragonfruit"\./);
  store.calls.length = 0;
  r = await say(brain, 'show me');
  assert.match(r.text, /^Tell me a product or a category/);
  r = await say(brain, 'order history');
  assert.match(r.text, /^I cannot look up orders or accounts here/);
  assert.deepEqual(store.calls, []);
});

test('cheapest, price and stock', async () => {
  const { brain } = setup();
  let r = await say(brain, 'cheapest avocado');
  assert.equal(r.text, 'The cheapest avocado right now:');
  assert.deepEqual(r.products.map((p) => p.title), ['Avocado Shepard', 'Avocado Mini', 'Avocado Hass']);
  goodChips(r);
  r = await say(brain, 'avocado under 10 dhs');
  assert.equal(r.text, `Avocado under ${money(1000)}:`);
  assert.deepEqual(r.products.map((p) => p.title), ['Avocado Shepard', 'Avocado Mini']);
  r = await say(brain, 'avocado under 5');
  assert.equal(r.text, `Nothing for "avocado" is under ${money(500)} right now. The cheapest is Avocado Shepard at ${money(800)}.`);
  r = await say(brain, 'cheapest blueberry');
  assert.equal(r.products[0].title, 'Organic Blueberry Punnet');
  r = await say(brain, 'cheapest');
  assert.match(r.text, /Tell me what to look for/);
  r = await say(brain, 'How much is strawberry?');
  assert.equal(r.text, `Strawberry is ${money(1800)}, down from ${money(2400)}.`);
  goodChips(r);
  r = await say(brain, 'price of blueberry');
  assert.equal(r.text, `Blueberry is ${money(1600)}. It is sold out right now.`);
  r = await say(brain, 'is blueberry in stock');
  assert.equal(r.text, 'Blueberry is sold out right now. Organic Blueberry Punnet is in stock.');
  r = await say(brain, 'Is avocado available?');
  assert.equal(r.text, 'Yes, Avocado Hass is in stock.');
  goodChips(r);
});

test('recipes: one product per ingredient, two searches at a time, Add all to cart', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'Ideas for a fruit salad');
  assert.equal(r.text, 'For a fruit salad, you could use:');
  assert.deepEqual(r.products.map((p) => p.title),
    ['Strawberry', 'Zespri Kiwi Sungold', 'Banana Chiquita', 'Organic Blueberry Punnet']);
  assert.equal(store.maxInFlight, 2);
  assert.equal(store.lines.length, 0);
  assert.equal(r.suggestions[0], 'Add all to cart');
  goodChips(r);
  r = await brain.reply({ chip: 'Add all to cart' });
  assert.match(r.text, /^Added 4 products to your cart: Strawberry, Zespri Kiwi Sungold, Banana Chiquita and Organic Blueberry Punnet\.$/);
  assert.equal(r.cartChanged, true);
  assert.equal(store.lines.length, 4);
  r = await say(brain, 'how do I make guacamole');
  assert.equal(r.text, 'For guacamole, you could use these. I could not find lime in stock right now.');
  assert.deepEqual(r.products.map((p) => p.title), ['Avocado Shepard', 'Tomatoes Cherry', 'Red Onions']);
  r = await setup({ products: [item(70, 'Demo Bread', 500)] }).brain.reply({ text: 'something for a bbq' });
  assert.equal(r.text, 'I could not find the ingredients for a BBQ in stock right now.');
  assert.deepEqual(r.suggestions.slice(0, 2), ['Ideas for breakfast', 'Ideas for a fruit salad']);
  r = await brain.reply({ option: 'recipes' });
  assert.equal(r.suggestions.length, 6);
  goodChips(r);
});

test('help, greeting, thanks, unknown option', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'help');
  assert.equal(r.showOptions, true);
  assert.equal(r.text, 'Here is what I can help with. Tap an option or type your question.');
  r = await say(brain, 'hi');
  assert.match(r.text, /^Hello! /);
  r = await say(brain, 'thanks');
  assert.equal(r.text, 'You are welcome. Is there anything else I can help with?');
  r = await say(brain, 'bye');
  assert.equal(r.text, 'Thank you for shopping with Fresh Market. Come back any time.');
  r = await brain.reply({ option: 'nope' });
  assert.equal(r.showOptions, true);
  assert.deepEqual(store.calls, []);
  assert.equal(brain.greeting().text, 'Hi! Demo greeting.');
  assert.equal(brain.greeting().showOptions, true);
});

test('contact, payment, favourites use the website', async () => {
  const { store, brain } = setup();
  let r = await brain.reply({ option: 'care' });
  assert.match(r.text, /800 0 000000 \(toll-free\) or care@example\.test/);
  assert.deepEqual(r.links.map((l) => l.url), ['tel:8000000000', 'mailto:care@example.test', '/pages/contact']);
  r = await say(brain, 'payment methods');
  assert.match(r.text, /Visa, Mastercard and Apple Pay/);
  assert.equal(r.links, undefined);
  await store.add(5102, 1);
  r = await say(brain, 'payment methods');
  assert.deepEqual(r.links, [{ label: 'Open cart', url: '/cart' }]);
  r = await say(brain, 'my favourites');
  assert.match(r.text, /app/);
  assert.deepEqual(r.links, [{ label: 'My account', url: '/account' }]);
  goodChips(r);
});

test('delivery and Express answer from the theme delivery state', async () => {
  const { store, brain } = setup();
  let r = await say(brain, 'Delivery information');
  assert.match(r.text, /seven emirates/);
  assert.match(r.text, /"Deliver to" button/);
  r = await say(brain, 'Is Express open?');
  assert.match(r.text, /8 AM to 10 PM\. Choose your area with the "Deliver to" button/);
  store.delivery_ = { area: 'Demo Hills', emirate: 'Dubai', mode: 'market', expressOpen: true,
    expressAvailableHere: true, promiseMarket: 'Today within 6 hours to Demo Hills · by 4 PM',
    promiseExpress: 'Get it in 25–35 min to Demo Hills' };
  r = await say(brain, 'delivery');
  assert.equal(r.text, 'Delivering to Demo Hills, Dubai: Today within 6 hours to Demo Hills · by 4 PM. Express: get it ' +
    'in 25–35 min to Demo Hills for items marked Express. Any delivery fee is shown at checkout.');
  assert.deepEqual(r.links, [{ label: 'Shop Express items', url: '/collections/express' }]);
  r = await say(brain, 'is express open now');
  assert.equal(r.text, 'Express reaches Demo Hills, Dubai for items marked Express. It is open until 10 PM. Get it in ' +
    '25–35 min to Demo Hills.');
  store.delivery_ = Object.assign({}, store.delivery_, { expressOpen: false });
  r = await say(brain, 'is express open now');
  assert.equal(r.text, 'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market delivers today within 6 hours ' +
    'to Demo Hills · by 4 PM.');
  store.delivery_ = Object.assign({}, store.delivery_, { expressAvailableHere: false });
  r = await say(brain, 'delivery');
  assert.match(r.text, /Express: not available in your area\./);
  assert.equal(r.links, undefined);
  r = await say(brain, 'can I get it in 1 hour');
  assert.match(r.text, /^Express isn't available in Demo Hills yet\./);
});

test('the Express collection starts with the status for the area', async () => {
  const { store, brain } = setup({ collections: { express: [item(60, 'Express Demo Kiwi', 900)] } });
  let r = await say(brain, 'Show 1Hr Express');
  assert.equal(r.text, 'A few products from 1Hr Express:');
  store.delivery_ = { area: 'Demo Hills', expressOpen: false, expressAvailableHere: true };
  r = await say(brain, 'Show 1Hr Express');
  assert.equal(r.text, 'Express is closed right now. It runs 8 AM to 10 PM. A few products from 1Hr Express:');
});

test('store failures become replies; a 429 is retried once', async () => {
  const { store, brain } = setup();
  store.error = new TypeError('Failed to fetch');
  let r = await say(brain, 'Find avocado');
  assert.equal(r.text, 'I could not reach the store. Check your connection and try again.');
  r = await say(brain, 'Ideas for breakfast');
  assert.equal(r.text, 'I could not reach the store. Check your connection and try again.');
  store.error = Object.assign(new Error('x'), { userMessage: 'The store is busy.' });
  r = await say(brain, 'Find avocado');
  assert.equal(r.text, 'The store is busy.');
  store.error = Object.assign(new Error('Too many'), { status: 429 });
  let n = 0;
  const search = store.search;
  store.search = async (q, l) => { if (n++ === 0) throw store.error; store.error = null; return search(q, l); };
  r = await say(brain, 'Find avocado');
  assert.equal(r.text, 'Here is what I found for "avocado".');
  assert.equal(n, 2);
  r = await say(brain, 'Find avocado');
  assert.ok(Array.isArray(r.suggestions) && r.suggestions.length > 0);
});

test('every reply has suggestions; products have the public shape', async () => {
  const { brain } = setup();
  const r = await say(brain, 'Find avocado');
  assert.deepEqual(Object.keys(r.products[0]).sort(),
    ['available', 'compareAtFils', 'id', 'image', 'priceFils', 'subtitle', 'title', 'url', 'variantId']);
  const none = await say(brain, 'show me');
  assert.deepEqual(none.suggestions, B.DEFAULT_SUGGESTIONS);
});
