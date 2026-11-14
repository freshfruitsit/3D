import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import { decimalToFils, filsToDecimal, formatAed } from '../lib/money.js';
import {
  AREAS,
  EMIRATES,
  deliveryPromise,
  expressPromise,
  formatHour,
  formatLeft,
  isDeliverablePoint,
  isExpressTagged,
  marketPromise,
  pinOf,
  placeLabel,
  provinceCode,
  uaeHours,
} from '../lib/delivery.js';
import { normaliseMobile, parseBearer, parseIdempotencyKey, parseOrderBody, parseQuoteBody, parseVariantId } from '../lib/validate.js';
import { loadConfig } from '../lib/config.js';
import { ConfigError } from '../lib/errors.js';
import { ENV, uae } from './helpers/fake-shopify.js';
import { orderBody, quoteBody } from './helpers/setup.js';

const area = (name) => AREAS.find((a) => a.name === name);
const limits = { maxLines: 50, maxQtyPerLine: 50 };

describe('money', () => {
  test('decimal strings to fils without floats', () => {
    assert.equal(decimalToFils('19.95'), 1995);
    assert.equal(decimalToFils('20'), 2000);
    assert.equal(decimalToFils('20.5'), 2050);
    assert.equal(decimalToFils('0.10'), 10);
    assert.equal(decimalToFils('1234567.89'), 123456789);
    assert.equal(decimalToFils('0.125'), 13);
    assert.equal(decimalToFils('0.124'), 12);
    assert.equal(decimalToFils('-5.00'), -500);
    assert.equal(decimalToFils(' 25 '), 2500);
    assert.equal(decimalToFils(25), 2500);
    assert.equal(decimalToFils(0.1 + 0.2), 30);
    for (const bad of ['', 'abc', '1,000.00', '1e3', '.5', null, undefined, {}, NaN]) {
      assert.equal(decimalToFils(bad), null, String(bad));
    }
  });

  test('fils to Shopify decimal and to text', () => {
    assert.equal(filsToDecimal(2500), '25.00');
    assert.equal(filsToDecimal(5), '0.05');
    assert.equal(filsToDecimal(0), '0.00');
    assert.equal(filsToDecimal(-150), '-1.50');
    assert.throws(() => filsToDecimal(1.5));
    assert.equal(formatAed(123456), 'AED 1,234.56');
    assert.equal(formatAed(1995), 'AED 19.95');
  });
});

describe('delivery rules (ported from the app; values from its delivery_rules_test.dart)', () => {
  test('emirate -> Shopify province code', () => {
    assert.deepEqual(
      Object.fromEntries(Object.keys(EMIRATES).map((e) => [e, provinceCode(e)])),
      { dubai: 'DU', auh: 'AZ', shj: 'SH', ajm: 'AJ', uaq: 'UQ', rak: 'RK', fuj: 'FU' },
    );
    assert.equal(provinceCode('xx'), null);
    assert.equal(provinceCode('toString'), null);
  });

  test('UAE time is UTC+4', () => {
    assert.equal(uaeHours(new Date(Date.UTC(2026, 10, 12, 20, 30))), 0.5);
    assert.equal(uaeHours(new Date(uae(10))), 10);
  });

  test('formatHour and formatLeft', () => {
    const hours = { 0: '12 AM', 0.5: '12:30 AM', 8: '8 AM', 12: '12 PM', 16.25: '4:15 PM', 18: '6 PM', 22: '10 PM', 24: '12 AM', 24.25: '12:15 AM' };
    for (const [h, want] of Object.entries(hours)) assert.equal(formatHour(Number(h)), want);
    assert.equal(formatHour(16 + 5 / 60), '4:05 PM');
    assert.equal(formatLeft(0), '0m');
    assert.equal(formatLeft(-1), '0m');
    assert.equal(formatLeft(3 + 20 / 60), '3h 20m');
    assert.equal(formatLeft(10), '10h 0m');
  });

  test('Express distance, cover and ETA per area', () => {
    const table = {
      'Dubai Marina': [24.782042, false, 55, '50–60 min'],
      'Downtown Dubai': [9.32491, true, 35, '30–40 min'],
      Mirdif: [7.498334, true, 30, '25–35 min'],
      'Jebel Ali': [38.230866, false, 75, '70–80 min'],
      'Al Majaz': [16.867663, true, 45, '40–50 min'],
      'Al Faseel': [97.86132, false, 165, '160–170 min'],
    };
    for (const [name, [km, covered, eta, range]] of Object.entries(table)) {
      const ex = expressPromise(area(name), new Date(uae(12)));
      assert.ok(Math.abs(ex.km - km) < 1e-5, name);
      assert.equal(ex.covered, covered, name);
      assert.equal(ex.etaMinutes, eta, name);
      assert.equal(ex.range, range, name);
    }
    const atHub = expressPromise({ lat: 25.18, lng: 55.36 }, new Date(uae(12)));
    assert.equal(atHub.etaMinutes, 20);
    assert.equal(atHub.range, '15–25 min');
  });

  test('Express runs 8 AM to before 10 PM', () => {
    const open = (h, m) => expressPromise(area('Mirdif'), new Date(uae(h, m))).open;
    assert.equal(open(7, 59), false);
    assert.equal(open(8, 0), true);
    assert.equal(open(21, 59), true);
    assert.equal(open(22, 0), false);
  });

  test('Fresh Market promise around the 6 PM cut-off', () => {
    const cases = [
      [0, 0, true, 'Today by 6 AM', '18h 0m'],
      [10, 7, true, 'Today by 4:15 PM', '7h 53m'],
      [16, 16, true, 'Today by 10:30 PM', '1h 44m'],
      [17, 59, true, 'Today by 12 AM', '1m'],
      [18, 0, false, 'Tomorrow by 11 AM', null],
      [23, 59, false, 'Tomorrow by 11 AM', null],
    ];
    for (const [h, m, today, slot, left] of cases) {
      const mk = marketPromise('dubai', new Date(uae(h, m)));
      assert.equal(mk.today, today, `${h}:${m}`);
      assert.equal(mk.slot, slot, `${h}:${m}`);
      assert.equal(mk.left, left, `${h}:${m}`);
    }
    assert.equal(marketPromise('auh', new Date(uae(10))).line, 'Today within 6 hours');
    assert.equal(marketPromise('auh', new Date(uae(18))).line, 'Tomorrow morning before 11 AM');
  });

  test('the promise the server writes on the order', () => {
    const mirdif = area('Mirdif');
    assert.deepEqual(deliveryPromise('market', mirdif, new Date(uae(10))), { promise: 'Today within 6 hours', expressProblem: null });
    assert.deepEqual(deliveryPromise('market', mirdif, new Date(uae(19))), { promise: 'Tomorrow morning before 11 AM', expressProblem: null });
    assert.deepEqual(deliveryPromise('express', mirdif, new Date(uae(12))), { promise: '25–35 min', expressProblem: null });
    assert.equal(deliveryPromise('express', mirdif, new Date(uae(6))).promise, 'Today from 8 AM');
    assert.equal(deliveryPromise('express', mirdif, new Date(uae(23))).promise, 'Tomorrow from 8 AM');
    const far = deliveryPromise('express', area('Jebel Ali'), new Date(uae(12)));
    assert.equal(far.expressProblem, "Express isn't available in Jebel Ali yet. Fresh Market delivers today within 6 hours.");
  });

  test('labels, pins, tags and deliverable points', () => {
    assert.equal(placeLabel('Mirdif', 'dubai'), 'Mirdif, Dubai');
    assert.equal(placeLabel('Downtown Dubai', 'dubai'), 'Downtown Dubai');
    assert.equal(placeLabel('Al Nahyan', 'auh'), 'Al Nahyan, Abu Dhabi');
    assert.equal(pinOf(25.08, 55.14), '25.08000,55.14000');
    assert.equal(isExpressTagged(['Fruit', ' 1HR-delivery ']), true);
    assert.equal(isExpressTagged(['1hr delivery']), false);
    assert.equal(isExpressTagged(undefined), false);
    assert.equal(isDeliverablePoint(25.22, 55.42), true);
    assert.equal(isDeliverablePoint(23.0, 53.0), false); // empty desert, > 60 km from every area
  });
});

describe('validation', () => {
  test('variant ids in every shape the app may send', () => {
    assert.deepEqual(parseVariantId(44123), { gid: 'gid://shopify/ProductVariant/44123', numeric: '44123' });
    assert.deepEqual(parseVariantId('44123'), { gid: 'gid://shopify/ProductVariant/44123', numeric: '44123' });
    assert.deepEqual(parseVariantId('gid://shopify/ProductVariant/44123'), { gid: 'gid://shopify/ProductVariant/44123', numeric: '44123' });
    for (const bad of [0, -1, 1.5, '0', 'abc', 'gid://shopify/Product/1', null, {}, 2 ** 60]) assert.equal(parseVariantId(bad), null, String(bad));
  });

  test('UAE mobiles become E.164', () => {
    assert.equal(normaliseMobile('050 123 4567'), '+971501234567');
    assert.equal(normaliseMobile('+971 (0)50 123 4567'), '+971501234567');
    assert.equal(normaliseMobile('00971501234567'), '+971501234567');
    assert.equal(normaliseMobile('٠٥٠١٢٣٤٥٦٧'), '+971501234567');
    assert.equal(normaliseMobile('+44 20 7946 0958'), '+442079460958');
    assert.equal(normaliseMobile('+971 50 123 456'), null);
    assert.equal(normaliseMobile('12345'), null);
    assert.equal(normaliseMobile(''), null);
  });

  test('a good quote body passes', () => {
    const r = parseQuoteBody(quoteBody(), limits);
    assert.deepEqual(r.errors, []);
    assert.equal(r.lines.length, 2);
    assert.equal(r.delivery.pin, '25.22000,55.42000');
  });

  test('malformed quote bodies give field errors', () => {
    const cases = [
      [null, 'body'],
      [[], 'body'],
      [quoteBody({ lines: [] }), 'lines'],
      [quoteBody({ lines: 'x' }), 'lines'],
      [quoteBody({ lines: [{ variantId: 'abc', quantity: 1 }] }), 'lines[0].variantId'],
      [quoteBody({ lines: [{ variantId: 1, quantity: 0 }] }), 'lines[0].quantity'],
      [quoteBody({ lines: [{ variantId: 1, quantity: 1.5 }] }), 'lines[0].quantity'],
      [quoteBody({ lines: [{ variantId: 1, quantity: '2' }] }), 'lines[0].quantity'],
      [quoteBody({ lines: [{ variantId: 1, quantity: 51 }] }), 'lines[0].quantity'],
      [quoteBody({ lines: [{ variantId: 1, quantity: 1 }, { variantId: '1', quantity: 1 }] }), 'lines[1].variantId'],
      [quoteBody({ lines: Array.from({ length: 51 }, (_, i) => ({ variantId: i + 1, quantity: 1 })) }), 'lines'],
      [quoteBody({ lines: [{ variantId: 1, quantity: 1, unitPriceFils: 1.5 }] }), 'lines[0].unitPriceFils'],
      [quoteBody({ delivery: null }), 'delivery'],
      [quoteBody({ delivery: { mode: 'drone', area: { name: 'Mirdif', emirate: 'dubai', lat: 25.22, lng: 55.42 } } }), 'delivery.mode'],
      [quoteBody({ delivery: { mode: 'market', area: { name: 'Mirdif', emirate: 'oman', lat: 25.22, lng: 55.42 } } }), 'delivery.area.emirate'],
      [quoteBody({ delivery: { mode: 'market', area: { name: '', emirate: 'dubai', lat: 25.22, lng: 55.42 } } }), 'delivery.area.name'],
      [quoteBody({ delivery: { mode: 'market', area: { name: 'X', emirate: 'dubai', lat: '25.2', lng: 55.42 } } }), 'delivery.area'],
      [quoteBody({ delivery: { mode: 'market', area: { name: 'London', emirate: 'dubai', lat: 51.5, lng: -0.12 } } }), 'delivery.area'],
      [quoteBody({ delivery: { mode: 'market', area: { name: 'Desert', emirate: 'auh', lat: 23.0, lng: 53.0 } } }), 'delivery.area'],
    ];
    for (const [body, field] of cases) {
      const r = parseQuoteBody(body, limits);
      assert.ok(r.errors.length > 0, JSON.stringify(body)?.slice(0, 80));
      assert.equal(r.errors[0].field, field, JSON.stringify(body)?.slice(0, 120));
    }
  });

  test('order bodies: address, phone, emirate match, text limits', () => {
    const ok = parseOrderBody(orderBody(), limits);
    assert.deepEqual(ok.errors, []);
    assert.equal(ok.address.phone, '+971501234567');
    assert.equal(ok.instructions, 'Call when you arrive');

    const field = (overrides) => parseOrderBody(orderBody(overrides), limits).errors.map((e) => e.field);
    const addr = (patch) => ({ address: { ...orderBody().address, ...patch } });
    assert.deepEqual(field(addr({ phone: '123' })), ['address.phone']);
    assert.deepEqual(field(addr({ phone: undefined })), ['address.phone']);
    assert.deepEqual(field(addr({ emirate: 'shj' })), ['address.emirate']);
    assert.deepEqual(field(addr({ firstName: '   ' })), ['address.firstName']);
    assert.deepEqual(field(addr({ address1: 'x'.repeat(171) })), ['address.address1']);
    assert.deepEqual(field(addr({ address2: undefined })), []);
    assert.deepEqual(field({ address: null }), ['address']);
    assert.deepEqual(field({ instructions: 'x'.repeat(201) }), ['instructions']);
    assert.deepEqual(field({ instructions: 42 }), ['instructions']);
    assert.deepEqual(field({ note: 'line one\r\nline two' }), []);
    assert.deepEqual(field({ delivery: { ...orderBody().delivery, pin: 'here' } }), ['delivery.pin']);
    assert.deepEqual(field({ expectedTotalFils: -1 }), ['expectedTotalFils']);
    assert.equal(parseOrderBody(orderBody({ note: 'a\r\n\r\n\r\n\u0007b' }), limits).note, 'a\n\nb');
  });

  test('headers', () => {
    assert.equal(parseIdempotencyKey('3F0B6A2E-5C1D-4E8F-9A7B-1C2D3E4F5A6B'), '3f0b6a2e-5c1d-4e8f-9a7b-1c2d3e4f5a6b');
    assert.equal(parseIdempotencyKey('not-a-uuid'), null);
    assert.equal(parseIdempotencyKey(null), null);
    assert.equal(parseBearer('Bearer abc.def'), 'abc.def');
    assert.equal(parseBearer('bearer abc'), 'abc');
    assert.equal(parseBearer('abc'), null);
    assert.equal(parseBearer('Bearer '), null);
    assert.equal(parseBearer(null), null);
  });
});

describe('config', () => {
  test('defaults and parsing', () => {
    const c = loadConfig({ SHOPIFY_STORE_DOMAIN: 'testtfm.myshopify.com' });
    assert.equal(c.apiVersion, '2026-10');
    assert.equal(c.deliveryFeeFils, 2500);
    assert.equal(c.freeDeliveryFromFils, 20000);
    assert.equal(c.minOrderFils, 0);
    assert.equal(c.maxLines, 50);
    assert.equal(c.maxQtyPerLine, 50);
    assert.equal(c.maxOrdersPerHour, 5);
    const d = loadConfig({ ...ENV, DELIVERY_FEE_AED: '12.5', MIN_ORDER_AED: '30', MAX_ORDERS_PER_HOUR: '3' });
    assert.equal(d.deliveryFeeFils, 1250);
    assert.equal(d.minOrderFils, 3000);
    assert.equal(d.maxOrdersPerHour, 3);
  });

  test('bad values name the variable, never the value', () => {
    assert.throws(() => loadConfig({}), (e) => e instanceof ConfigError && /SHOPIFY_STORE_DOMAIN/.test(e.message));
    assert.throws(
      () => loadConfig({ ...ENV, DELIVERY_FEE_AED: 'twenty', SHOPIFY_API_VERSION: 'latest', SHOPIFY_CLIENT_SECRET: 'shhh' }),
      (e) => /DELIVERY_FEE_AED/.test(e.message) && /SHOPIFY_API_VERSION/.test(e.message) && !/shhh|twenty/.test(e.message),
    );
    assert.throws(() => loadConfig({ ...ENV, MAX_LINES: '500' }), /MAX_LINES/);
  });
});

describe('Vercel entry points', () => {
  test('api/*.js default-export a fetch handler', async () => {
    for (const name of ['health', 'quote', 'orders']) {
      const mod = await import(`../api/${name}.js`);
      assert.equal(typeof mod.default.fetch, 'function', name);
    }
    const { default: health } = await import('../api/health.js');
    const res = await health.fetch(new Request('https://x.test/api/health'));
    assert.deepEqual(await res.json(), { ok: true, version: '1.0.0' });
  });
});
