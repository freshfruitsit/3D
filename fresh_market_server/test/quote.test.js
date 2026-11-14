import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import { JEBEL_ALI, MIRDIF, post, quoteBody, setup } from './helpers/setup.js';
import { responses, uae, variant } from './helpers/fake-shopify.js';

async function quote(t, body, opts) {
  const res = await t.quote(post('/api/quote', body), opts);
  return { status: res.status, body: await res.json(), res };
}

describe('POST /api/quote', () => {
  test('happy path: Shopify prices, fee, promise', async () => {
    const t = setup();
    const { status, body, res } = await quote(t, quoteBody());
    assert.equal(status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.deepEqual(body, {
      lines: [
        { variantId: 2001, title: 'Fresh Strawberries', variantTitle: '500 GM', quantity: 2, unitPriceFils: 1995, lineTotalFils: 3990, available: true },
        { variantId: '2004', title: 'Tomatoes', variantTitle: '500 GM', quantity: 3, unitPriceFils: 250, lineTotalFils: 750, available: true },
      ],
      subtotalFils: 4740,
      deliveryFeeFils: 2500,
      totalFils: 7240,
      currency: 'AED',
      deliveryPromise: 'Today within 6 hours',
      problems: [],
      minOrderFils: 0,
    });
    const [call] = t.shop.ops('FreshMarketVariants');
    assert.deepEqual(call.variables.ids, ['gid://shopify/ProductVariant/2001', 'gid://shopify/ProductVariant/2004']);
    assert.equal(t.shop.tokenRequests, 1, 'client credentials token fetched once');
  });

  test('the app cannot set prices: unitPriceFils only reports price_changed', async () => {
    const t = setup();
    const { body } = await quote(t, quoteBody({ lines: [{ variantId: 2001, quantity: 1, unitPriceFils: 1500 }] }));
    assert.equal(body.lines[0].unitPriceFils, 1995);
    assert.equal(body.subtotalFils, 1995);
    assert.deepEqual(body.problems, [
      { variantId: 2001, kind: 'price_changed', message: 'The price of Fresh Strawberries changed from AED 15.00 to AED 19.95.' },
    ]);
  });

  test('delivery fee below the free threshold, free at exactly AED 200', async () => {
    const t = setup();
    t.shop.variants.set('gid://shopify/ProductVariant/3001', variant(3001, { price: '199.99' }));
    t.shop.variants.set('gid://shopify/ProductVariant/3002', variant(3002, { price: '200.00' }));
    const below = await quote(t, quoteBody({ lines: [{ variantId: 3001, quantity: 1 }] }));
    assert.equal(below.body.deliveryFeeFils, 2500);
    assert.equal(below.body.totalFils, 19999 + 2500);
    const at = await quote(t, quoteBody({ lines: [{ variantId: 3002, quantity: 1 }] }));
    assert.equal(at.body.deliveryFeeFils, 0);
    assert.equal(at.body.totalFils, 20000);
  });

  test('fee, threshold and minimum come from the environment', async () => {
    const t = setup({ env: { DELIVERY_FEE_AED: '10', FREE_DELIVERY_FROM_AED: '50', MIN_ORDER_AED: '30' } });
    const { body } = await quote(t, quoteBody({ lines: [{ variantId: 2001, quantity: 1 }] }));
    assert.equal(body.deliveryFeeFils, 1000);
    assert.equal(body.minOrderFils, 3000);
    const big = await quote(t, quoteBody({ lines: [{ variantId: 2001, quantity: 3 }] }));
    assert.equal(big.body.deliveryFeeFils, 0);
  });

  test('sold out, missing and inactive items are not charged', async () => {
    const t = setup();
    t.shop.variants.set('gid://shopify/ProductVariant/3003', variant(3003, { price: '5.00', status: 'DRAFT' }));
    const { body } = await quote(t, quoteBody({ lines: [
      { variantId: 2008, quantity: 1 },
      { variantId: 9999, quantity: 1 },
      { variantId: 3003, quantity: 1 },
      { variantId: 2004, quantity: 2 },
    ] }));
    assert.deepEqual(body.lines.map((l) => [l.variantId, l.available, l.lineTotalFils]), [[2008, false, 0], [9999, false, 0], [3003, false, 0], [2004, true, 500]]);
    assert.deepEqual(body.problems.map((p) => [p.variantId, p.kind]), [[2008, 'sold_out'], [9999, 'sold_out'], [3003, 'sold_out']]);
    assert.equal(body.problems[0].message, 'Blueberries is sold out.');
    assert.equal(body.problems[1].message, 'This item is no longer sold.');
    assert.equal(body.subtotalFils, 500);
  });

  test('tracked stock below the quantity: qty_reduced, or sold_out at zero', async () => {
    const t = setup();
    const { body } = await quote(t, quoteBody({ lines: [{ variantId: 2009, quantity: 5 }] }));
    assert.equal(body.lines[0].quantity, 2);
    assert.equal(body.lines[0].lineTotalFils, 15000);
    assert.deepEqual(body.problems, [{ variantId: 2009, kind: 'qty_reduced', message: 'Only 2 of Lamb left, so we changed 5 to 2.' }]);

    t.shop.variants.get('gid://shopify/ProductVariant/2009').inventoryQuantity = 0;
    const zero = await quote(t, quoteBody({ lines: [{ variantId: 2009, quantity: 1 }] }));
    assert.equal(zero.body.problems[0].kind, 'sold_out');
    assert.equal(zero.body.deliveryFeeFils, 0);
    assert.equal(zero.body.totalFils, 0);
  });

  test('CONTINUE policy or untracked stock never limits the quantity', async () => {
    const t = setup();
    t.shop.variants.set('gid://shopify/ProductVariant/3004', variant(3004, { price: '1.00', tracked: true, policy: 'CONTINUE', qty: -3 }));
    const { body } = await quote(t, quoteBody({ lines: [{ variantId: 3004, quantity: 10 }, { variantId: 2004, quantity: 50 }] }));
    assert.deepEqual(body.problems, []);
    assert.equal(body.lines[0].quantity, 10);
  });

  test('Express: items without the 1hr-delivery tag are flagged', async () => {
    const t = setup();
    const { body } = await quote(t, quoteBody({
      lines: [{ variantId: 2001, quantity: 1 }, { variantId: 2004, quantity: 1 }, { variantId: 2007, quantity: 1 }],
      delivery: { mode: 'express', area: { ...MIRDIF } },
    }));
    assert.equal(body.deliveryPromise, '25–35 min');
    assert.deepEqual(body.problems, [{ variantId: 2004, kind: 'not_express', message: "Tomatoes isn't on Express. Switch to Fresh Market or remove it." }]);
  });

  test('Express outside the 20 km zone is refused with a basket-level problem', async () => {
    const t = setup();
    const { body } = await quote(t, quoteBody({ lines: [{ variantId: 2001, quantity: 1 }], delivery: { mode: 'express', area: { ...JEBEL_ALI } } }));
    assert.deepEqual(body.problems, [{ variantId: null, kind: 'not_express', message: "Express isn't available in Jebel Ali yet. Fresh Market delivers today within 6 hours." }]);
    assert.equal(body.deliveryPromise, 'Today within 6 hours');
  });

  test('promise after the 6 PM cut-off and Express while closed', async () => {
    const t = setup({ now: uae(19, 30) });
    assert.equal((await quote(t, quoteBody())).body.deliveryPromise, 'Tomorrow morning before 11 AM');
    const t2 = setup({ now: uae(22, 30) });
    const ex = await quote(t2, quoteBody({ lines: [{ variantId: 2001, quantity: 1 }], delivery: { mode: 'express', area: { ...MIRDIF } } }));
    assert.equal(ex.body.deliveryPromise, 'Tomorrow from 8 AM');
    assert.deepEqual(ex.body.problems, []);
  });

  test('malformed input: 400 bad JSON, 415 wrong type, 413 too large, 422 fields, 405 method', async () => {
    const t = setup();
    const bad = await t.quote(post('/api/quote', '{"lines": ['));
    assert.equal(bad.status, 400);
    assert.equal((await bad.json()).error, 'bad_json');

    const type = await t.quote(new Request('https://x.test/api/quote', { method: 'POST', headers: { 'content-type': 'text/plain' }, body: '{}' }));
    assert.equal(type.status, 415);

    const big = await t.quote(post('/api/quote', JSON.stringify({ pad: 'x'.repeat(70_000) })));
    assert.equal(big.status, 413);

    const invalid = await t.quote(post('/api/quote', quoteBody({ lines: [{ variantId: 2001, quantity: -1 }] })));
    assert.equal(invalid.status, 422);
    const j = await invalid.json();
    assert.equal(j.field, 'lines[0].quantity');
    assert.equal(typeof j.message, 'string');
    assert.ok(Array.isArray(j.errors));

    const get = await t.quote(new Request('https://x.test/api/quote'));
    assert.equal(get.status, 405);
    assert.equal(get.headers.get('allow'), 'POST');
    assert.equal(t.shop.calls.length, 0, 'no Shopify calls for bad input');
  });

  test('Shopify throttling on a quote: 503 busy at once, no retry (orders keep the points)', async () => {
    const t = setup();
    t.shop.override('FreshMarketVariants', responses.throttled);
    const { status, body, res } = await quote(t, quoteBody());
    assert.equal(status, 503);
    assert.deepEqual([body.error, body.retryable], ['busy', true]);
    assert.equal(res.headers.get('retry-after'), '1'); // (120 - 20) / 100 = 1 s
    assert.equal(t.shop.ops('FreshMarketVariants').length, 1);
    assert.deepEqual(t.sleeps, []);
  });

  test('while Shopify\'s bucket is low, quotes are refused without calling Shopify; orders still go through', async () => {
    const t = setup();
    t.shop.cost = { requestedQueryCost: 150, actualQueryCost: 150, throttleStatus: { maximumAvailable: 2000, currentlyAvailable: 300, restoreRate: 100 } };
    assert.equal((await quote(t, quoteBody())).status, 200); // learns the bucket is at 300 of 2000
    const refused = await quote(t, quoteBody());
    assert.equal(refused.status, 503);
    assert.equal(refused.body.error, 'busy');
    // Reserve is 40 % of 2000 = 800 points; 500 short at 100/s = 5 s.
    assert.equal(refused.res.headers.get('retry-after'), '5');
    assert.equal(t.shop.ops('FreshMarketVariants').length, 1);

    const { orderBody, orderHeaders } = await import('./helpers/setup.js');
    const placed = await t.orders(post('/api/orders', orderBody(), orderHeaders()));
    assert.equal(placed.status, 201);

    t.clock.now += 5_000; // the bucket refills at 100 points a second
    t.shop.cost = { requestedQueryCost: 50, actualQueryCost: 20, throttleStatus: { maximumAvailable: 2000, currentlyAvailable: 1950, restoreRate: 100 } };
    assert.equal((await quote(t, quoteBody())).status, 200);
  });

  test('Shopify down: 503 {retryable: true}; reads are retried first', async () => {
    const t = setup();
    for (let i = 0; i < 3; i++) t.shop.override('FreshMarketVariants', responses.serverError);
    const { status, body, res } = await quote(t, quoteBody());
    assert.equal(status, 503);
    assert.equal(body.retryable, true);
    assert.ok(res.headers.get('x-request-id'));
    assert.equal(t.shop.ops('FreshMarketVariants').length, 3);
  });

  test('a shop that does not sell in AED is a setup error, not a wrong price', async () => {
    const t = setup();
    t.shop.override('FreshMarketVariants', () => new Response(JSON.stringify({ data: { shop: { currencyCode: 'USD' }, nodes: [] } }), { status: 200 }));
    const { status, body } = await quote(t, quoteBody());
    assert.equal(status, 500);
    assert.equal(body.error, 'server_misconfigured');
    assert.equal(body.retryable, false);
  });

  test('missing environment: 500 without leaking names or values to the app', async () => {
    const t = setup({ env: { SHOPIFY_STORE_DOMAIN: '' } });
    const { status, body } = await quote(t, quoteBody());
    assert.equal(status, 500);
    assert.doesNotMatch(JSON.stringify(body), /SHOPIFY/);
    assert.match(JSON.stringify(t.logs), /SHOPIFY_STORE_DOMAIN/);
  });
});

describe('GET /api/health', () => {
  test('ok and version', async () => {
    const t = setup();
    const res = await t.health(new Request('https://x.test/api/health'));
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { ok: true, version: '1.0.0' });
    assert.equal((await t.health(new Request('https://x.test/api/health', { method: 'POST' }))).status, 405);
  });
});
