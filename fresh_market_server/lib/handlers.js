// The three routes, built from injectable dependencies so the tests can
// pass a mocked fetch and a fixed clock. api/*.js export them for Vercel.

import { loadConfig } from './config.js';
import { ApiError, unauthorized, validationError } from './errors.js';
import { json, log as defaultLog, readJson, route } from './http.js';
import { placeOrder, resetOrderCaches } from './orders.js';
import { resetAdminTokenCache } from './shopify-admin.js';
import { resetCustomerCaches } from './shopify-customer.js';
import { buildQuote, fetchVariants } from './quote.js';
import { parseBearer, parseIdempotencyKey, parseQuoteBody } from './validate.js';
import { VERSION } from './version.js';

/**
 * @typedef {object} Deps
 * @property {typeof fetch} [fetch]
 * @property {() => number} [now]
 * @property {(ms: number) => Promise<void>} [sleep]
 * @property {Record<string, string|undefined>} [env]
 * @property {(fields: Record<string, unknown>) => void} [log]
 * @property {number} [budgetMs] how long a request may spend waiting on Shopify
 */

/** @param {Deps} deps */
function makeCtx(deps) {
  const now = deps.now ?? (() => Date.now());
  return {
    config: loadConfig(deps.env ?? process.env),
    fetch: deps.fetch ?? ((...args) => globalThis.fetch(...args)),
    now,
    sleep: deps.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms))),
    deadline: now() + (deps.budgetMs ?? 25_000),
    stats: { shopifyCalls: 0 },
    log: deps.log ?? defaultLog,
  };
}

/** Clears every module-scope cache (tests only). */
export function resetCaches() {
  resetAdminTokenCache();
  resetCustomerCaches();
  resetOrderCaches();
}

/** GET /api/health -> {ok: true, version} */
export function createHealthHandler(deps = {}) {
  return route('health', ['GET'], async () => json(200, { ok: true, version: VERSION }), { log: deps.log });
}

/** POST /api/quote */
export function createQuoteHandler(deps = {}) {
  return route(
    'quote',
    ['POST'],
    async (request, { logFields }) => {
      const ctx = makeCtx(deps);
      const body = await readJson(request);
      const parsed = parseQuoteBody(body, ctx.config);
      if (parsed.errors.length) throw validationError(parsed.errors);
      try {
        const variants = await fetchVariants(ctx, parsed.lines);
        const quote = buildQuote({ lines: parsed.lines, delivery: parsed.delivery, variants, config: ctx.config, now: new Date(ctx.now()) });
        logFields.lines = quote.lines.length;
        logFields.problems = quote.problems.map((p) => p.kind);
        return json(200, quote);
      } finally {
        logFields.shopifyCalls = ctx.stats.shopifyCalls;
      }
    },
    { log: deps.log },
  );
}

/** POST /api/orders */
export function createOrdersHandler(deps = {}) {
  return route(
    'orders',
    ['POST'],
    async (request, { logFields }) => {
      const token = parseBearer(request.headers.get('authorization'));
      if (!token) throw unauthorized('Sign in to place an order.');
      const rawKey = request.headers.get('idempotency-key');
      const idemKey = parseIdempotencyKey(rawKey);
      if (!idemKey) {
        throw validationError([{ field: 'Idempotency-Key', message: 'Send an Idempotency-Key header with a new UUID for each order.' }]);
      }
      const ctx = makeCtx(deps);
      const body = await readJson(request);
      try {
        const result = await placeOrder(ctx, { token, idemKey, body, logFields });
        return json(result.status, result.body, result.headers ?? {});
      } catch (err) {
        if (err instanceof ApiError) logFields.outcome ??= err.code;
        throw err;
      } finally {
        logFields.shopifyCalls = ctx.stats.shopifyCalls;
      }
    },
    { log: deps.log },
  );
}
