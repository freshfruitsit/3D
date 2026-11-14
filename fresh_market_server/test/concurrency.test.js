// Parallel requests and Shopify's lagging search: the per-customer lock
// ($app:checkout metafield, changed only with compareDigest) must keep the
// hourly limit and the Idempotency-Key exact even when search finds nothing.

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

import { KEY, orderBody, orderHeaders, post, setup } from './helpers/setup.js';
import { CUSTOMER } from './helpers/fake-shopify.js';

const HOUR_LAG = 3600_000; // search finds nothing made during the test

async function order(t, body = orderBody(), headers = orderHeaders()) {
  const res = await t.orders(post('/api/orders', body, headers));
  return { status: res.status, body: await res.json(), res };
}

function lockJson(value) {
  return JSON.stringify({ v: 1, key: '', owner: '', until: 0, draftId: '', orderId: '', orderName: '', totalFils: 0, promise: '', recent: [], ...value });
}

describe('one order at a time per customer', () => {
  test('15 parallel orders with different keys never pass MAX_ORDERS_PER_HOUR, even with search lagging', async () => {
    const t = setup({ parallel: true });
    t.shop.searchLagMs = HOUR_LAG;
    const results = await Promise.all(Array.from({ length: 15 }, () => order(t, orderBody(), orderHeaders({ key: randomUUID() }))));
    const statuses = results.map((r) => r.status);
    const created = statuses.filter((s) => s === 201).length;
    assert.ok(t.shop.orders.length <= 5, `orders: ${t.shop.orders.length}`);
    assert.ok(t.shop.orders.length >= 1);
    assert.equal(created, t.shop.orders.length);
    for (const r of results) {
      assert.ok([201, 429, 503].includes(r.status), String(r.status));
      if (r.status === 503) assert.deepEqual([r.body.error, r.body.retryable], ['in_progress', true]);
    }
    // Every order went through the lock, so its list holds them all.
    assert.equal(t.shop.lockOf(CUSTOMER.id).recent.length, t.shop.orders.length);
  });

  test('the same key sent twice in parallel makes one order; both get it', async () => {
    const t = setup({ parallel: true });
    t.shop.searchLagMs = HOUR_LAG;
    const [a, b] = await Promise.all([order(t), order(t)]);
    assert.deepEqual([a.status, b.status], [201, 201]);
    assert.equal(t.shop.orders.length, 1);
    assert.deepEqual(a.body, b.body);
    assert.deepEqual([a.res.headers.get('idempotent-replayed'), b.res.headers.get('idempotent-replayed')].sort(), ['true', null].sort());
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 1);
  });

  test('sequential orders are counted from the lock when search lags behind', async () => {
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '2' } });
    t.shop.searchLagMs = HOUR_LAG;
    assert.equal((await order(t, orderBody(), orderHeaders({ key: randomUUID() }))).status, 201);
    assert.equal((await order(t, orderBody(), orderHeaders({ key: randomUUID() }))).status, 201);
    const third = await order(t, orderBody(), orderHeaders({ key: randomUUID() }));
    assert.equal(third.status, 429);
    assert.equal(t.shop.orders.length, 2);
  });

  test('a retry after the lock recorded the order is answered from the lock, without search', async () => {
    const t = setup();
    t.shop.searchLagMs = HOUR_LAG;
    const first = await order(t);
    const again = await order(t);
    assert.equal(again.status, 201);
    assert.deepEqual(again.body, first.body);
    assert.equal(again.res.headers.get('idempotent-replayed'), 'true');
    assert.equal(t.shop.orders.length, 1);
  });

  test('while another order holds the lock: wait, then 503 in_progress; no variant read, no draft', async () => {
    const t = setup();
    t.shop.locks.set(CUSTOMER.id, { value: lockJson({ key: randomUUID(), owner: randomUUID(), until: t.clock.now + 80_000 }), compareDigest: 'd0' });
    const { status, body, res } = await order(t);
    assert.equal(status, 503);
    assert.deepEqual([body.error, body.retryable], ['in_progress', true]);
    assert.equal(res.headers.get('retry-after'), '3');
    assert.equal(t.shop.ops('FreshMarketLock').length, 10);
    assert.equal(t.shop.ops('FreshMarketVariants').length, 0);
    assert.equal(t.shop.drafts.length, 0);
  });

  test('a lock that ran out (crashed request) is taken over', async () => {
    const t = setup();
    t.shop.locks.set(CUSTOMER.id, { value: lockJson({ key: randomUUID(), owner: randomUUID(), until: t.clock.now - 1 }), compareDigest: 'd0' });
    assert.equal((await order(t)).status, 201);
    assert.equal(t.shop.lockOf(CUSTOMER.id).key, KEY);
  });

  test('crash after draftOrderComplete: the retry finds the order through the lock\'s draftId', async () => {
    const t = setup();
    // The first attempt completes the order, then the final lock write is lost.
    let lockSets = 0;
    t.shop.override('FreshMarketLockSet', (v) => t.shop.admin('FreshMarketLockSet', v));
    t.shop.override('FreshMarketLockSet', (v) => t.shop.admin('FreshMarketLockSet', v));
    t.shop.override('FreshMarketLockSet', () => {
      lockSets++;
      throw new TypeError('fetch failed');
    });
    t.shop.searchLagMs = HOUR_LAG;
    const first = await order(t);
    assert.equal(first.status, 201);
    assert.equal(lockSets, 1);
    assert.equal(t.shop.lockOf(CUSTOMER.id).orderId, '', 'lock never heard of the order');

    t.clock.now += 91_000; // the lock runs out
    const again = await order(t);
    assert.equal(again.status, 201);
    assert.equal(again.body.orderId, first.body.orderId);
    assert.equal(again.res.headers.get('idempotent-replayed'), 'true');
    assert.equal(t.shop.orders.length, 1);
    assert.equal(t.shop.lockOf(CUSTOMER.id).orderId, first.body.orderId, 'lock repaired');
  });

  test('the lock write after draftOrderCreate fails: the release still records the draft; the retry resumes it', async () => {
    const t = setup();
    t.shop.override('FreshMarketLockSet', (v) => t.shop.admin('FreshMarketLockSet', v)); // acquire
    t.shop.override('FreshMarketLockSet', () => {
      throw new TypeError('fetch failed'); // draftId write lost
    });
    t.shop.searchLagMs = HOUR_LAG;
    const first = await order(t);
    assert.equal(first.status, 503);
    const lock = t.shop.lockOf(CUSTOMER.id);
    assert.deepEqual([lock.until, lock.draftId], [0, 'gid://shopify/DraftOrder/900001']);
    const second = await order(t);
    assert.equal(second.status, 201);
    assert.equal(t.shop.ops('FreshMarketDraftCreate').length, 1);
    assert.equal(t.shop.orders.length, 1);
  });

  test('an open leftover draft with the same key is deleted, not completed', async () => {
    const t = setup();
    // An earlier attempt's draftOrderCreate timed out after Shopify made the draft.
    t.shop.override('FreshMarketDraftCreate', (v) => {
      t.shop.admin('FreshMarketDraftCreate', v);
      throw new TypeError('fetch failed');
    });
    t.shop.searchLagMs = HOUR_LAG; // the retry's gate search cannot see that draft
    assert.equal((await order(t)).status, 503);
    t.shop.searchLagMs = 0; // by the time the draft is polled, search shows it
    const second = await order(t);
    assert.equal(second.status, 201);
    assert.equal(t.shop.orders.length, 1);
    assert.equal(t.shop.drafts.filter((d) => d.status === 'OPEN').length, 0);
  });

  test('metafieldsSet refused (no write_customers or wrong type): 500 setup error, nothing created', async () => {
    const t = setup();
    t.shop.lockUserErrors = [{ field: ['metafields', '0', 'ownerId'], message: 'Access denied', code: 'APP_NOT_AUTHORIZED' }];
    const { status, body } = await order(t);
    assert.equal(status, 500);
    assert.equal(body.error, 'server_misconfigured');
    assert.equal(t.shop.drafts.length, 0);
    assert.match(JSON.stringify(t.logs), /metafieldsSet refused the order lock: APP_NOT_AUTHORIZED/);
  });

  test('a customer over the limit costs one small read, not the variant read', async () => {
    const t = setup({ env: { MAX_ORDERS_PER_HOUR: '1' } });
    assert.equal((await order(t, orderBody(), orderHeaders({ key: randomUUID() }))).status, 201);
    const before = t.shop.calls.length;
    for (let i = 0; i < 5; i++) assert.equal((await order(t, orderBody(), orderHeaders({ key: randomUUID() }))).status, 429);
    assert.deepEqual([...new Set(t.shop.calls.slice(before).map((c) => c.op))], ['FreshMarketGate']);
  });

  test('the lock holds ids and times only, no personal data', async () => {
    const t = setup();
    await order(t);
    const raw = t.shop.locks.get(CUSTOMER.id).value;
    for (const s of [CUSTOMER.email, CUSTOMER.token, 'Sara', 'Ahmed', '+971', 'Bay Square', 'Ring twice']) assert.equal(raw.includes(s), false, s);
  });
});
