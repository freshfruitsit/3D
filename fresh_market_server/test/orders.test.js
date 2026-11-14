import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import { JEBEL_ALI, KEY, MIRDIF, orderBody, orderHeaders, post, setup } from './helpers/setup.js';
import { CUSTOMER, ENV, responses, uae } from './helpers/fake-shopify.js';

const KEY2 = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

async function order(t, body = orderBody(), headers = orderHeaders()) {
  const res = await t.orders(post('/api/orders', body, headers));
  return { status: res.status, body: await res.json(), res };
}

function uuid(n) {
  return `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
}

describe('POST /api/orders: happy path', () => {
  test('creates a COD order through a draft with due-on-fulfillment terms', async () => {
    const t = setup();
    const { status, body, res } = await order(t);
    assert.equal(status, 201);
    assert.deepEqual(body, {
      orderId: 'gid://shopify/Order/800001',
      orderName: '#1001',
      totalFils: 7240,
      deliveryPromise: 'Today within 6 hours',
      paymentMethod: 'Cash on Delivery',
    });
    assert.equal(res.headers.get('idempotent-replayed'), null);

    const [create] = t.shop.ops('FreshMarketDraftCreate');
    assert.deepEqual(create.variables.input, {
      purchasingEntity: { customerId: CUSTOMER.id },
      email: CUSTOMER.email,
      presentmentCurrencyCode: 'AED',
      acceptAutomaticDiscounts: false,
      lineItems: [
        { variantId: 'gid://shopify/ProductVariant/2001', quantity: 2 },
        { variantId: 'gid://shopify/ProductVariant/2004', quantity: 3 },
      ],
      shippingLine: { title: 'Fresh Market delivery', priceWithCurrency: { amount: '25.00', currencyCode: 'AED' } },
      shippingAddress: {
        firstName: 'Sara',
        lastName: 'Ahmed',
        address1: 'Bay Square, Building 5',
        address2: 'Flat 302',
        city: 'Mirdif',
        provinceCode: 'DU',
        countryCode: 'AE',
        phone: '+971501234567',
      },
      billingAddress: {
        firstName: 'Sara',
        lastName: 'Ahmed',
        address1: 'Bay Square, Building 5',
        address2: 'Flat 302',
        city: 'Mirdif',
        provinceCode: 'DU',
        countryCode: 'AE',
        phone: '+971501234567',
      },
      note: 'Ring twice',
      tags: ['app', 'cod', `idem-${KEY}`],
      customAttributes: [
        { key: 'Delivery mode', value: 'Fresh Market' },
        { key: 'Delivery area', value: 'Mirdif, Dubai' },
        { key: 'Delivery promise', value: 'Today within 6 hours' },
        { key: 'Delivery pin', value: '25.22000,55.42000' },
        { key: 'Delivery instructions', value: 'Call when you arrive' },
        { key: 'Source', value: 'Fresh Market app' },
        { key: 'Payment method', value: 'Cash on Delivery' },
      ],
      paymentTerms: { paymentTermsTemplateId: 'gid://shopify/PaymentTermsTemplate/7' },
    });
    assert.equal('phone' in create.variables.input, false, 'DraftOrderInput.phone is never set');

    const [complete] = t.shop.ops('FreshMarketDraftComplete');
    assert.deepEqual(complete.variables, { id: 'gid://shopify/DraftOrder/900001' });
    assert.equal(t.shop.orders[0].displayFinancialStatus, 'PENDING');
    assert.deepEqual(t.shop.orders[0].tags, ['app', 'cod', `idem-${KEY}`]);

    // Customer Account API: discovered endpoint, raw token without "Bearer".
    assert.equal(t.shop.discoveryRequests, 1);
    assert.equal(t.shop.customerRequests, 1);

    // The gate query asked for the right searches.
    const [prep] = t.shop.ops('FreshMarketGate');
    assert.equal(prep.variables.customerId, CUSTOMER.id);
    assert.equal(prep.variables.idem, `tag:"idem-${KEY}"`);
    assert.equal(prep.variables.recent, "customer_id:7001 created_at:>='2026-11-14T05:07:00Z'");
    assert.equal(prep.variables.recentFirst, 6);
    assert.equal(prep.variables.wantTerms, true);

    // The customer's lock now records the order and is free again.
    const lock = t.shop.lockOf(CUSTOMER.id);
    assert.deepEqual({ ...lock, owner: typeof lock.owner }, {
      v: 1,
      key: KEY,
      owner: 'string',
      until: 0,
      draftId: 'gid://shopify/DraftOrder/900001',
      orderId: 'gid://shopify/Order/800001',
      orderName: '#1001',
      totalFils: 7240,
      promise: 'Today within 6 hours',
      recent: [{ id: 'gid://shopify/Order/800001', t: t.clock.now }],
    });
    // Order of calls: the small gate read comes before the variant read.
    const ops = t.shop.calls.map((c) => c.op);
    assert.deepEqual(ops, ['FreshMarketGate', 'FreshMarketVariants', 'FreshMarketLockSet', 'FreshMarketDraftCreate', 'FreshMarketLockSet', 'FreshMarketDraftState', 'FreshMarketDraftComplete', 'FreshMarketLockSet']);
  });

  test('Express order: Express shipping line and the ETA as the promise', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody({
      lines: [{ variantId: 2001, quantity: 1 }, { variantId: 2007, quantity: 1 }],
      delivery: { mode: 'express', area: { ...MIRDIF }, promise: '25–35 min', pin: '25.22,55.42' },
    }));
    assert.equal(status, 201);
    assert.equal(body.deliveryPromise, '25–35 min');
    const input = t.shop.ops('FreshMarketDraftCreate')[0].variables.input;
    assert.deepEqual(input.shippingLine, { title: 'Express delivery', priceWithCurrency: { amount: '0.00', currencyCode: 'AED' } });
    assert.equal(body.totalFils, 1995 + 30000);
    assert.deepEqual(input.customAttributes.slice(0, 3), [
      { key: 'Delivery mode', value: 'Express' },
      { key: 'Delivery area', value: 'Mirdif, Dubai' },
      { key: 'Delivery promise', value: '25–35 min' },
    ]);
  });

  test('the server, not the app, decides the promise text, and says when it differs', async () => {
    const t = setup({ now: uae(18, 0) });
    const { body } = await order(t, orderBody({ delivery: { ...orderBody().delivery, promise: 'Today within 6 hours' } }));
    assert.equal(body.deliveryPromise, 'Tomorrow morning before 11 AM');
    assert.equal(body.promiseChanged, true);
    const attrs = t.shop.ops('FreshMarketDraftCreate')[0].variables.input.customAttributes;
    assert.deepEqual(attrs.find((a) => a.key === 'Delivery promise'), { key: 'Delivery promise', value: 'Tomorrow morning before 11 AM' });
    assert.match(JSON.stringify(t.logs), /"promiseChanged":true/);
  });

  test('no promiseChanged when the app showed the same promise or none', async () => {
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '5' } });
    const same = await order(t, orderBody(), orderHeaders({ key: uuid(1) }));
    assert.equal('promiseChanged' in same.body, false);
    const none = await order(t, orderBody({ delivery: { mode: 'market', area: { ...MIRDIF } } }), orderHeaders({ key: uuid(2) }));
    assert.equal(none.status, 201);
    assert.equal('promiseChanged' in none.body, false);
  });

  test('every emirate maps to its Shopify province code on the address', async () => {
    const places = [
      ['dubai', 'Mirdif', 25.22, 55.42, 'DU'],
      ['auh', 'Al Nahyan', 24.47, 54.38, 'AZ'],
      ['shj', 'Al Majaz', 25.33, 55.385, 'SH'],
      ['ajm', 'Al Nuaimiya', 25.39, 55.45, 'AJ'],
      ['uaq', 'Al Salamah', 25.56, 55.55, 'UQ'],
      ['rak', 'Al Nakheel', 25.79, 55.95, 'RK'],
      ['fuj', 'Al Faseel', 25.12, 56.33, 'FU'],
    ];
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '20' } });
    for (const [i, [emirate, name, lat, lng, code]] of places.entries()) {
      const { status } = await order(
        t,
        orderBody({
          delivery: { mode: 'market', area: { name, emirate, lat, lng }, pin: `${lat},${lng}` },
          address: { ...orderBody().address, emirate, city: name },
        }),
        orderHeaders({ key: uuid(i + 1) }),
      );
      assert.equal(status, 201, emirate);
      const input = t.shop.ops('FreshMarketDraftCreate').at(-1).variables.input;
      assert.equal(input.shippingAddress.provinceCode, code, emirate);
      assert.equal(input.shippingAddress.countryCode, 'AE');
    }
  });

  test('waits for draft.ready before completing', async () => {
    const t = setup();
    t.shop.readyAfterPolls = 3;
    const { status } = await order(t);
    assert.equal(status, 201);
    assert.equal(t.shop.ops('FreshMarketDraftState').length, 3);
    assert.equal(t.sleeps.length, 2);
  });

  test('logs carry no token, secret, email, phone or address', async () => {
    const t = setup();
    await order(t);
    const logs = JSON.stringify(t.logs);
    for (const secret of [CUSTOMER.token, ENV.SHOPIFY_CLIENT_SECRET, 'admin-token-1', CUSTOMER.email, '+971501234567', '050 123 4567', 'Bay Square', 'Ahmed', 'Ring twice']) {
      assert.equal(logs.includes(secret), false, secret);
    }
    assert.match(logs, /"outcome":"created"/);
    assert.match(logs, /"order":"#1001"/);
  });
});

describe('POST /api/orders: sign-in', () => {
  test('missing or malformed Authorization: 401 without calling Shopify', async () => {
    const t = setup();
    for (const headers of [orderHeaders({ token: null }), { ...orderHeaders(), authorization: 'Basic abc' }, { ...orderHeaders(), authorization: 'Bearer' }]) {
      const { status, body, res } = await order(t, orderBody(), headers);
      assert.equal(status, 401);
      assert.equal(body.error, 'unauthorized');
      assert.equal(res.headers.get('www-authenticate'), 'Bearer');
    }
    assert.equal(t.shop.customerRequests, 0);
    assert.equal(t.shop.calls.length, 0);
  });

  test('invalid or expired token: Shopify says 401, the app gets 401', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody(), orderHeaders({ token: 'shcat_expired' }));
    assert.equal(status, 401);
    assert.equal(body.error, 'unauthorized');
    assert.equal(t.shop.customerRequests, 1);
    assert.equal(t.shop.ops('FreshMarketGate').length, 0);
    assert.equal(t.shop.drafts.length, 0);
  });

  test('a checked token is cached briefly, then checked again', async () => {
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '10' } });
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(1) }))).status, 201);
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(2) }))).status, 201);
    assert.equal(t.shop.customerRequests, 1);
    assert.equal(t.shop.discoveryRequests, 1);
    assert.equal(t.shop.tokenRequests, 1, 'Admin token reused');
    t.clock.now += 61_000;
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(3) }))).status, 201);
    assert.equal(t.shop.customerRequests, 2);
  });

  test('Customer Account API throttled: 429 with Retry-After; down: 503 retryable', async () => {
    const t = setup();
    t.shop.override('customer', responses.customerThrottled);
    const limited = await order(t);
    assert.equal(limited.status, 429);
    assert.equal(limited.res.headers.get('retry-after'), '30');
    t.shop.override('customer', responses.serverError);
    const down = await order(t);
    assert.equal(down.status, 503);
    assert.equal(down.body.retryable, true);
  });
});

describe('POST /api/orders: the quote changed', () => {
  test('price changed since the app showed it: 409 with problems, nothing created', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody({ lines: [{ variantId: 2001, quantity: 2, unitPriceFils: 1800 }, { variantId: 2004, quantity: 3, unitPriceFils: 250 }] }));
    assert.equal(status, 409);
    assert.deepEqual(body.problems, [{ variantId: 2001, kind: 'price_changed', message: 'The price of Fresh Strawberries changed from AED 18.00 to AED 19.95.' }]);
    assert.equal(body.quote.totalFils, 7240);
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 0);
  });

  test('expected total differs: 409 price_changed for the basket', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody({ expectedTotalFils: 7000 }));
    assert.equal(status, 409);
    assert.deepEqual(body.problems, [{ variantId: null, kind: 'price_changed', message: 'Your total changed from AED 70.00 to AED 72.40.' }]);
  });

  test('sold out and reduced stock: 409, nothing created', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody({ lines: [{ variantId: 2008, quantity: 1 }, { variantId: 2009, quantity: 3 }, { variantId: 2004, quantity: 1 }] }));
    assert.equal(status, 409);
    assert.deepEqual(body.problems.map((p) => [p.variantId, p.kind]), [[2008, 'sold_out'], [2009, 'qty_reduced']]);
    assert.equal(t.shop.drafts.length, 0);
  });

  test('Shopify prices the draft differently than the quote: draft deleted, 409', async () => {
    const t = setup();
    t.shop.draftPrice.set('gid://shopify/ProductVariant/2004', '2.75');
    const { status, body } = await order(t);
    assert.equal(status, 409);
    assert.deepEqual(body.problems, [{ variantId: '2004', kind: 'price_changed', message: 'The price of Tomatoes changed from AED 2.50 to AED 2.75.' }]);
    assert.equal(t.shop.drafts.length, 0, 'draft deleted');
    assert.equal(t.shop.ops('FreshMarketDraftComplete').length, 0);
  });

  test('tax added on top (store not tax-inclusive): draft deleted, 500 setup error', async () => {
    const t = setup();
    t.shop.taxesIncluded = false;
    const { status, body } = await order(t);
    assert.equal(status, 500);
    assert.equal(body.error, 'server_misconfigured');
    assert.equal(t.shop.drafts.length, 0);
    assert.match(JSON.stringify(t.logs), /Include sales tax in product price/);
  });

  test('Express with an item not on Express: 409 not_express', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody({ delivery: { mode: 'express', area: { ...MIRDIF } } }));
    assert.equal(status, 409);
    assert.deepEqual(body.problems.map((p) => [p.variantId, p.kind]), [['2004', 'not_express']]);
    assert.equal(t.shop.drafts.length, 0);
  });

  test('Express outside the zone: 409 not_express for the basket', async () => {
    const t = setup();
    const { status, body } = await order(t, orderBody({
      lines: [{ variantId: 2001, quantity: 1 }],
      delivery: { mode: 'express', area: { ...JEBEL_ALI } },
    }));
    assert.equal(status, 409);
    assert.deepEqual(body.problems, [{ variantId: null, kind: 'not_express', message: "Express isn't available in Jebel Ali yet. Fresh Market delivers today within 6 hours." }]);
  });

  test('below MIN_ORDER_AED: 422 on lines', async () => {
    const t = setup({ env: { MIN_ORDER_AED: '100' } });
    const { status, body } = await order(t);
    assert.equal(status, 422);
    assert.equal(body.field, 'lines');
    assert.equal(body.message, 'The minimum order is AED 100.00. Add AED 52.60 more.');
    assert.equal(t.shop.drafts.length, 0);
  });
});

describe('POST /api/orders: idempotency', () => {
  test('a retry with the same key returns the same order and creates nothing', async () => {
    const t = setup();
    const first = await order(t);
    const second = await order(t);
    assert.equal(second.status, 201);
    assert.deepEqual(second.body, first.body);
    assert.equal(second.res.headers.get('idempotent-replayed'), 'true');
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 1);
    assert.equal(t.shop.orders.length, 1);
  });

  test('the retry is found through the order even if the draft is gone', async () => {
    const t = setup();
    const first = await order(t);
    t.shop.drafts.length = 0;
    const second = await order(t);
    assert.deepEqual(second.body, first.body);
    assert.equal(t.shop.orders.length, 1);
  });

  test('a lost response after the draft was made: the retry completes that draft', async () => {
    const t = setup();
    t.shop.override('FreshMarketDraftComplete', responses.networkError);
    const first = await order(t);
    assert.equal(first.status, 503);
    assert.equal(first.body.retryable, true);
    assert.equal(t.shop.drafts.length, 1);
    assert.equal(t.shop.ops('FreshMarketDraftComplete').length, 1, 'mutations are not resent blindly');

    const second = await order(t);
    assert.equal(second.status, 201);
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 1, 'no second draft');
    assert.equal(t.shop.orders.length, 1);
    assert.match(JSON.stringify(t.logs), /"resumed":true/);
  });

  test('an open draft that no longer matches the basket is replaced', async () => {
    const t = setup();
    t.shop.override('FreshMarketDraftComplete', responses.networkError);
    await order(t);
    const second = await order(t, orderBody({ lines: [{ variantId: 2004, quantity: 5 }] }));
    assert.equal(second.status, 201);
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 2);
    assert.equal(t.shop.ops('FreshMarketDraftDelete').length, 1);
    assert.equal(t.shop.drafts.filter((d) => d.status === 'OPEN').length, 0);
  });

  test('the same key from another customer: 422', async () => {
    const t = setup();
    await order(t);
    t.shop.customers.set('shcat_other', { id: 'gid://shopify/Customer/7999', emailAddress: { emailAddress: 'other@example.com' } });
    t.shop.override('FreshMarketCustomerByEmail', () => new Response(JSON.stringify({ data: { customerByIdentifier: { id: 'gid://shopify/Customer/7999' } } })));
    const { status, body } = await order(t, orderBody(), orderHeaders({ token: 'shcat_other' }));
    assert.equal(status, 422);
    assert.equal(body.field, 'Idempotency-Key');
    assert.equal(t.shop.orders.length, 1);
  });

  test('missing or malformed Idempotency-Key: 422', async () => {
    const t = setup();
    for (const key of [null, 'abc', '12345678-1234-1234-1234-1234567890']) {
      const { status, body } = await order(t, orderBody(), orderHeaders({ key }));
      assert.equal(status, 422);
      assert.equal(body.field, 'Idempotency-Key');
    }
    assert.equal(t.shop.customerRequests, 0);
  });

  test('two requests raced with one key: the later draft defers to the earlier one', async () => {
    const t = setup();
    // While this request creates its draft, a parallel request (same key) has
    // already created and completed an earlier draft the search did not show yet.
    t.shop.override('FreshMarketDraftCreate', (variables) => {
      t.shop.admin('FreshMarketDraftCreate', variables);
      const rival = t.shop.drafts.at(-1);
      t.shop.admin('FreshMarketDraftComplete', { id: rival.id });
      return t.shop.admin('FreshMarketDraftCreate', variables);
    });
    const { status, body } = await order(t);
    assert.equal(status, 201);
    assert.equal(body.orderName, '#1001');
    assert.equal(t.shop.orders.length, 1);
    assert.equal(t.shop.drafts.length, 1, 'the later duplicate draft was deleted');
    assert.equal(t.shop.ops('FreshMarketDraftComplete').length, 0, 'this request never completed a second draft');
  });
});

describe('POST /api/orders: abuse limits', () => {
  test('more than MAX_ORDERS_PER_HOUR orders in an hour: 429 with Retry-After', async () => {
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '2' } });
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(1) }))).status, 201);
    t.clock.now += 10 * 60_000;
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(2) }))).status, 201);
    t.clock.now += 61_000; // past the token cache too
    const third = await order(t, orderBody(), orderHeaders({ key: uuid(3) }));
    assert.equal(third.status, 429);
    assert.equal(third.body.error, 'rate_limited');
    // The first order was 11 min 1 s ago, so the window frees in 48 min 59 s.
    assert.equal(third.res.headers.get('retry-after'), String(60 * 60 - (11 * 60 + 1)));
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 2);

    // A retry of an earlier order is still answered while limited.
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(1) }))).status, 201);

    // An hour later the limit has passed.
    t.clock.now += 60 * 60_000;
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(4) }))).status, 201);
  });

  test('another customer\'s orders do not count', async () => {
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '1' } });
    t.shop.orders.push({ id: 'gid://shopify/Order/1', name: '#999', tags: ['app'], customer: { id: 'gid://shopify/Customer/1' }, customAttributes: [], totalFils: 100, createdAt: new Date(t.clock.now - 60_000).toISOString() });
    assert.equal((await order(t)).status, 201);
  });

  test('too many lines or too many of one item: 422', async () => {
    const t = setup({ env: { MAX_LINES: '2', MAX_QTY_PER_LINE: '5' } });
    const many = await order(t, orderBody({ lines: [1, 2, 3].map((i) => ({ variantId: 2000 + i, quantity: 1 })) }));
    assert.equal(many.status, 422);
    assert.equal(many.body.field, 'lines');
    const lots = await order(t, orderBody({ lines: [{ variantId: 2004, quantity: 6 }] }));
    assert.equal(lots.status, 422);
    assert.equal(lots.body.field, 'lines[0].quantity');
  });
});

describe('POST /api/orders: Shopify trouble', () => {
  test('throttled draftOrderCreate is resent after the wait (it never ran)', async () => {
    const t = setup();
    t.shop.override('FreshMarketDraftCreate', responses.throttled);
    const { status } = await order(t);
    assert.equal(status, 201);
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 2);
    assert.equal(t.shop.drafts.length, 1);
  });

  test('5xx on draftOrderCreate is not resent: 503 retryable, and the retry works', async () => {
    const t = setup();
    t.shop.override('FreshMarketDraftCreate', responses.serverError);
    const first = await order(t);
    assert.equal(first.status, 503);
    assert.deepEqual([first.body.error, first.body.retryable], ['unavailable', true]);
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 1);
    const second = await order(t);
    assert.equal(second.status, 201);
  });

  test('throttled on every attempt: 503 busy with Retry-After', async () => {
    const t = setup();
    for (let i = 0; i < 3; i++) t.shop.override('FreshMarketGate', responses.throttled);
    const { status, body, res } = await order(t);
    assert.equal(status, 503);
    assert.equal(body.error, 'busy');
    assert.equal(body.retryable, true);
    assert.ok(Number(res.headers.get('retry-after')) >= 1);
  });

  test('an expired Admin token is replaced once, then the call is resent', async () => {
    const t = setup();
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(1) }))).status, 201);
    t.shop.adminTokens.length = 0; // Shopify forgets the token
    assert.equal((await order(t, orderBody(), orderHeaders({ key: uuid(2) }))).status, 201);
    assert.equal(t.shop.tokenRequests, 2);
  });

  test('wrong client secret: 500 setup error, secret never logged', async () => {
    const t = setup({ env: { SHOPIFY_CLIENT_SECRET: 'wrong-secret' } });
    const { status, body } = await order(t);
    assert.equal(status, 500);
    assert.equal(body.retryable, false);
    const logs = JSON.stringify(t.logs);
    assert.match(logs, /invalid_client/);
    assert.equal(logs.includes('wrong-secret'), false);
  });

  test('legacy SHOPIFY_ADMIN_TOKEN skips the client credentials grant', async () => {
    const t = setup({ env: { SHOPIFY_ADMIN_TOKEN: 'shpat_legacy', SHOPIFY_CLIENT_ID: '', SHOPIFY_CLIENT_SECRET: '' } });
    t.shop.legacyToken = 'shpat_legacy';
    assert.equal((await order(t)).status, 201);
    assert.equal(t.shop.tokenRequests, 0);
  });

  test('draftOrderCreate userErrors become 422 with the app\'s field names', async () => {
    const t = setup();
    t.shop.createUserErrors = [{ field: ['input', 'shippingAddress', 'phone'], message: 'Phone is invalid' }];
    const { status, body } = await order(t);
    assert.equal(status, 422);
    assert.equal(body.field, 'address.phone');
    assert.equal(body.message, 'Phone is invalid');
  });

  test('draftOrderComplete userErrors: draft deleted, 422 on order, Shopify\'s text only in the log', async () => {
    const t = setup();
    t.shop.completeUserErrors = [{ field: null, message: 'Item "Sara\'s box" for sara@example.com is no longer available' }];
    const { status, body } = await order(t);
    assert.equal(status, 422);
    assert.equal(body.field, 'order');
    assert.equal('detail' in body, false);
    assert.deepEqual(body.errors, [{ field: 'order', message: 'We could not place the order. Please check your basket and try again.' }]);
    assert.equal(t.shop.drafts.length, 0);
    const line = t.logs.find((l) => l.route === 'orders');
    assert.equal(line.detail, 'draftOrderComplete: Item "…" for [email] is no longer available');
    // The lock was let go, so the customer can try again at once.
    assert.equal(t.shop.lockOf(CUSTOMER.id).until, 0);
  });

  test('Customer Account API id unknown to Admin: found by verified email instead', async () => {
    const t = setup();
    t.shop.adminCustomers = new Set(['gid://shopify/Customer/5555']);
    t.shop.adminCustomerByEmail = 'gid://shopify/Customer/5555';
    const first = await order(t);
    assert.equal(first.status, 201);
    const creates = t.shop.ops('FreshMarketDraftCreate');
    assert.equal(creates.length, 1);
    assert.deepEqual(creates[0].variables.input.purchasingEntity, { customerId: 'gid://shopify/Customer/5555' });
    assert.equal(t.shop.lockOf('gid://shopify/Customer/5555').orderName, '#1001');
    // The retry is still recognised as the same customer's order.
    const again = await order(t);
    assert.deepEqual(again.body, first.body);
  });

  test('customer unknown to Admin and not found by email: 500 setup error, nothing created', async () => {
    const t = setup();
    t.shop.adminCustomers = new Set();
    const { status, body } = await order(t);
    assert.equal(status, 500);
    assert.equal(body.error, 'server_misconfigured');
    assert.equal(t.shop.drafts.length, 0);
  });

  test('no FULFILLMENT payment terms template: 500 setup error, nothing created', async () => {
    const t = setup();
    t.shop.termsTemplates = [{ id: 'gid://shopify/PaymentTermsTemplate/1', name: 'Due on receipt', paymentTermsType: 'RECEIPT' }];
    const { status } = await order(t);
    assert.equal(status, 500);
    assert.equal(t.shop.drafts.length, 0);
  });

  test('SHOPIFY_PAYMENT_TERMS_TEMPLATE_ID overrides the lookup', async () => {
    const t = setup({ env: { SHOPIFY_PAYMENT_TERMS_TEMPLATE_ID: 'gid://shopify/PaymentTermsTemplate/42' } });
    assert.equal((await order(t)).status, 201);
    assert.equal(t.shop.ops('FreshMarketGate')[0].variables.wantTerms, false);
    assert.deepEqual(t.shop.ops('FreshMarketDraftCreate')[0].variables.input.paymentTerms, { paymentTermsTemplateId: 'gid://shopify/PaymentTermsTemplate/42' });
  });
});

describe('POST /api/orders: malformed input', () => {
  test('bad JSON 400, field errors 422, GET 405', async () => {
    const t = setup();
    const bad = await t.orders(post('/api/orders', '{nope', orderHeaders()));
    assert.equal(bad.status, 400);
    const missing = await order(t, { lines: [{ variantId: 2001, quantity: 1 }] });
    assert.equal(missing.status, 422);
    assert.deepEqual(missing.body.errors.map((e) => e.field), ['delivery', 'address']);
    const get = await t.orders(new Request('https://x.test/api/orders', { headers: orderHeaders() }));
    assert.equal(get.status, 405);
  });
});
