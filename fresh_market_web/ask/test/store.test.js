// Node tests for the Shopify store adapter and helpers in fm-ask.js.
// Run: node --test fresh_market_web/ask/test/*.test.js
// All products, prices, keys and areas below are fictional demo data.
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const A = require('../assets/fm-ask.js');

const IMG = 'https://cdn.example.com/demo.jpg';

function demoJs(handle, o = {}) {
  return Object.assign({
    id: 101, title: 'Demo Apple', handle, vendor: 'Demo Farm', tags: ['origin:Demo Land', 'Fruits'],
    price: 1250, compare_at_price: null, available: true, featured_image: '//cdn.example.com/demo.jpg',
    variants: [{ id: 9001, price: 1250, compare_at_price: 1500, available: true }]
  }, o);
}

function fakeFetch(routes, log = []) {
  return (url, init) => {
    log.push({ url, init });
    const path = url.replace(/^\//, '');
    for (const [re, fn] of routes) {
      const m = re.exec(path);
      if (m) {
        const [status, body] = fn(m, init);
        return Promise.resolve({ ok: status < 400, status, json: () => Promise.resolve(body) });
      }
    }
    return Promise.resolve({ ok: false, status: 404, json: () => Promise.resolve({}) });
  };
}

test('toFils and formatAED', () => {
  assert.equal(A.toFils('11.50'), 1150);
  assert.equal(A.toFils(1150), 1150);
  assert.equal(A.toFils('1,250.00'), 125000);
  assert.equal(A.toFils(null), null);
  assert.equal(A.toFils('abc'), null);
  assert.equal(A.formatAED(3125), 'AED 31.25');
});

test('subtitle: size from title or handle, origin from tag', () => {
  assert.equal(A.sizeOf('Demo Grapes 500g', ''), '500 g');
  assert.equal(A.sizeOf('Demo Berry', 'demo-berry-land-125g-pack'), '125 g');
  assert.equal(A.sizeOf('Demo Juice 1.5 Ltr', ''), '1.5 L');
  assert.equal(A.sizeOf('Demo Layer Cake', 'demo-layer-cake'), null);
  assert.equal(A.subtitleOf('Demo Berry', 'demo-berry-250g', ['origin:Demo Land']), '250 g · Demo Land');
  assert.equal(A.subtitleOf('Demo Berry', 'demo-berry', 'Fruits, origin:Demo Land'), 'Demo Land');
});

test('safeUrl allows only http(s), tel, mailto and same-site paths', () => {
  assert.equal(A.safeUrl('/collections/demo'), '/collections/demo');
  assert.equal(A.safeUrl('tel:0000'), 'tel:0000');
  assert.equal(A.safeUrl('https://example.com/x'), 'https://example.com/x');
  assert.equal(A.safeUrl('javascript:alert(1)'), null);
  assert.equal(A.safeUrl('//evil.example'), null);
  assert.equal(A.safeUrl('data:text/html,x'), null);
});

test('mapJsProduct and mapJsonProduct', () => {
  const p = A.mapJsProduct(demoJs('demo-apple-1kg'), '/');
  assert.deepEqual(
    [p.id, p.variantId, p.priceFils, p.compareAtFils, p.available, p.subtitle, p.url],
    [101, 9001, 1250, 1500, true, '1 kg · Demo Land', '/products/demo-apple-1kg']);
  assert.equal(p.image, 'https://cdn.example.com/demo.jpg?width=120');
  const j = A.mapJsonProduct({
    id: 7, title: 'Demo Pear 6 pcs', handle: 'demo-pear', tags: [], vendor: 'V',
    images: [{ src: IMG }],
    variants: [{ id: 1, price: '9.00', compare_at_price: '8.00', available: false }, { id: 2, price: '9.50', compare_at_price: null, available: true }]
  }, '/ar');
  assert.deepEqual([j.variantId, j.priceFils, j.compareAtFils, j.available, j.subtitle, j.url], [2, 950, null, true, '6 pcs', '/ar/products/demo-pear']);
});

test('search resolves variants through /products/<handle>.js', async () => {
  const log = [];
  const store = A.createStore({
    root: '/', document: null, storage: null,
    fetch: fakeFetch([
      [/^search\/suggest\.json/, () => [200, { resources: { results: { products: [{ handle: 'demo-a', title: 'A', price: '1.00' }, { handle: 'demo-b', title: 'B', price: '2.00', available: true }] } } }]],
      [/^products\/demo-a\.js$/, m => [200, demoJs('demo-a')]],
      [/^products\/demo-b\.js$/, () => [500, {}]]
    ], log)
  });
  const res = await store.search('demo', 3);
  assert.equal(res.length, 2);
  assert.equal(res[0].variantId, 9001);
  assert.equal(res[1].variantId, null); // fell back to the suggest data
  assert.equal(res[1].priceFils, 200);
  assert.match(log[0].url, /resources%5Blimit%5D=3/);
  assert.deepEqual(await store.search('  ', 3), []);
});

test('collections skips empty ones; collection 404 is empty; product 404 is null', async () => {
  const store = A.createStore({
    root: '/', document: null, storage: null,
    fetch: fakeFetch([
      [/^collections\.json/, () => [200, { collections: [{ handle: 'demo-full', title: 'Full', products_count: 3 }, { handle: 'demo-empty', title: 'Empty', products_count: 0 }] }]]
    ])
  });
  assert.deepEqual(await store.collections(), [{ handle: 'demo-full', title: 'Full' }]);
  assert.deepEqual(await store.collection('nope', 5), []);
  assert.equal(await store.product('nope'), null);
});

test('cart, add, setQuantity and clear post JSON and report errors', async () => {
  const log = [];
  const cart = { item_count: 2, total_price: 2500, items: [{ key: 'demo:key1', variant_id: 9001, product_title: 'Demo Apple', quantity: 2, final_line_price: 2500 }] };
  const ran = [];
  const store = A.createStore({
    root: '/', document: null, storage: null,
    bridge: { sectionIds: () => ['demo-section'], run: (action, ctx, lines, req) => { ran.push([action, ctx, lines]); return req(); } },
    fetch: fakeFetch([
      [/^cart\.js$/, () => [200, cart]],
      [/^cart\/add\.js$/, (m, init) => JSON.parse(init.body).items[0].quantity > 5 ? [422, { status: 422, description: 'Only 5 left.' }] : [200, { items: [] }]],
      [/^cart\/change\.js$/, () => [200, cart]],
      [/^cart\/clear\.js$/, () => [200, { items: [] }]]
    ], log)
  });
  assert.deepEqual(await store.cart(), { items: [{ key: 'demo:key1', variantId: 9001, title: 'Demo Apple', quantity: 2, lineFils: 2500 }], itemCount: 2, totalFils: 2500 });
  assert.deepEqual(await store.add(9001, 1), { ok: true });
  const addCall = log.find(c => c.url === '/cart/add.js');
  assert.deepEqual(JSON.parse(addCall.init.body).items, [{ id: 9001, quantity: 1 }]);
  assert.equal(JSON.parse(addCall.init.body).sections, 'demo-section');
  assert.deepEqual(await store.add(9001, 9), { ok: false, error: 'Only 5 left.' });
  assert.deepEqual(await store.add(null, 1), { ok: false, error: 'This product cannot be added here.' });
  assert.deepEqual(await store.setQuantity('demo:key1', 0), { ok: true });
  assert.deepEqual(await store.clear(), { ok: true });
  assert.deepEqual(ran.map(r => r[0]), ['add', 'add', 'remove', 'remove']);
  assert.deepEqual(ran[3][2], [{ id: 'demo:key1', quantity: 0 }]);
});

test('add reports a network failure instead of throwing', async () => {
  const store = A.createStore({ root: '/', document: null, storage: null, fetch: () => Promise.reject(new TypeError('offline')) });
  const r = await store.add(9001, 1);
  assert.equal(r.ok, false);
  assert.match(r.error, /could not reach the store/);
});

function fakeDoc({ config, chipWhere, marketSub, expressSub, bodyExpress }) {
  const els = {
    '[data-tfm-delivery-config]': config ? { textContent: JSON.stringify(config) } : null,
    '[data-tfm-chip-where]': chipWhere != null ? { textContent: chipWhere } : null,
    '[data-tfm-market-sub]': marketSub != null ? { textContent: marketSub } : null,
    '[data-tfm-express-sub]': expressSub != null ? { textContent: expressSub } : null
  };
  return { querySelector: s => els[s] || null, body: { classList: { contains: c => c === 'tfm-mode-express' && !!bodyExpress } } };
}
const storageWith = v => ({ getItem: () => (v === undefined ? null : JSON.stringify(v)) });
const CFG = { hub: { lat: '25.00', lng: '55.00' }, expressKm: 20, expressOpen: 8, expressClose: 22 };

test('delivery: reads area, mode, hours, coverage and header promises', () => {
  const noon = new Date(Date.UTC(2026, 0, 5, 8, 0)); // 12:00 in the UAE
  const area = { name: 'Demo Bay', em: 'dubai', lat: 25.05, lng: 55.05 };
  const d = A.readDelivery(fakeDoc({ config: CFG, chipWhere: 'Demo Bay', marketSub: 'Today within 6 hours', expressSub: '25–35 min' }), storageWith({ mode: 'express', area }), noon, '');
  assert.deepEqual(d, { area: 'Demo Bay', emirate: 'Dubai', mode: 'express', expressOpen: true, expressAvailableHere: true, promiseMarket: 'Today within 6 hours', promiseExpress: '25–35 min' });

  const far = { name: 'Demo Hills', em: 'rak', lat: 25.9, lng: 56.0 };
  const late = new Date(Date.UTC(2026, 0, 5, 19, 0)); // 23:00 in the UAE
  const d2 = A.readDelivery(fakeDoc({ config: CFG, chipWhere: 'Choose your area', marketSub: 'Full range · same day', expressSub: 'In about 60 min' }), storageWith({ mode: 'market', area: far }), late, '');
  assert.deepEqual(d2, { area: 'Demo Hills', emirate: 'Ras Al Khaimah', mode: 'market', expressOpen: false, expressAvailableHere: false, promiseMarket: null, promiseExpress: null });

  const d3 = A.readDelivery(fakeDoc({ config: CFG }), storageWith(undefined), noon, '?tfm_time=23');
  assert.deepEqual(d3, { area: null, emirate: null, mode: 'market', expressOpen: false, expressAvailableHere: null, promiseMarket: null, promiseExpress: null });

  const d4 = A.readDelivery(null, null, noon, '');
  assert.equal(d4.mode, null);
  assert.equal(d4.expressOpen, null);
});
