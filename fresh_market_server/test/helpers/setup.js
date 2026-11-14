import { createHealthHandler, createOrdersHandler, createQuoteHandler, resetCaches } from '../../lib/handlers.js';
import { ENV, NOON_ISH, CUSTOMER, fakeShopify } from './fake-shopify.js';

/**
 * Fresh handlers wired to a fake Shopify, a fixed clock and instant sleeps.
 * A sleep moves the clock on, except with `parallel: true`, where it only
 * lets the other requests run (many requests share one clock there).
 */
export function setup({ now = NOON_ISH, env = {}, parallel = false, budgetMs } = {}) {
  resetCaches();
  const clock = { now };
  const shop = fakeShopify({ now: () => clock.now });
  const sleeps = [];
  const logs = [];
  const deps = {
    fetch: shop.fetch,
    now: () => clock.now,
    sleep: async (ms) => {
      sleeps.push(ms);
      if (parallel) await new Promise((resolve) => setImmediate(resolve));
      else clock.now += ms;
    },
    ...(budgetMs ? { budgetMs } : {}),
    env: { ...ENV, ...env },
    log: (fields) => logs.push(fields),
  };
  return {
    shop,
    clock,
    sleeps,
    logs,
    deps,
    quote: createQuoteHandler(deps),
    orders: createOrdersHandler(deps),
    health: createHealthHandler(deps),
  };
}

export function post(path, body, headers = {}) {
  return new Request(`https://fresh-market-server.test${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });
}

export const KEY = '3f0b6a2e-5c1d-4e8f-9a7b-1c2d3e4f5a6b';

export function orderHeaders({ token = CUSTOMER.token, key = KEY } = {}) {
  const h = {};
  if (token !== null) h.authorization = `Bearer ${token}`;
  if (key !== null) h['idempotency-key'] = key;
  return h;
}

export const MIRDIF = Object.freeze({ name: 'Mirdif', emirate: 'dubai', lat: 25.22, lng: 55.42 });
export const JEBEL_ALI = Object.freeze({ name: 'Jebel Ali', emirate: 'dubai', lat: 25.01, lng: 55.03 });

export function quoteBody(overrides = {}) {
  return {
    lines: [
      { variantId: 2001, quantity: 2 },
      { variantId: '2004', quantity: 3 },
    ],
    delivery: { mode: 'market', area: { ...MIRDIF } },
    ...overrides,
  };
}

export function orderBody(overrides = {}) {
  return {
    lines: [
      { variantId: 2001, quantity: 2 },
      { variantId: '2004', quantity: 3 },
    ],
    delivery: { mode: 'market', area: { ...MIRDIF }, promise: 'Today within 6 hours', pin: '25.22000,55.42000' },
    address: {
      firstName: 'Sara',
      lastName: 'Ahmed',
      address1: 'Bay Square, Building 5',
      address2: 'Flat 302',
      city: 'Mirdif',
      emirate: 'dubai',
      phone: '050 123 4567',
    },
    instructions: 'Call when you arrive',
    note: 'Ring twice',
    ...overrides,
  };
}
