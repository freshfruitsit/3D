// Shopify Admin GraphQL client: access token (client credentials grant, or a
// legacy fixed token), retries on throttling, refresh on auth failure.
//
// Docs relied on (copies in server_docs/):
// - Client credentials grant:
//   https://shopify.dev/docs/apps/build/authentication-authorization/client-credentials-grant
//   POST https://{shop}.myshopify.com/admin/oauth/access_token, form body
//   grant_type=client_credentials, client_id, client_secret; response
//   {access_token, scope, expires_in}; "Tokens expire after 24 hours, so the
//   example caches the token and refreshes it before expiry"; "Don't send a
//   `scope` parameter."; send the token as X-Shopify-Access-Token.
// - Errors: https://shopify.dev/docs/api/admin-graphql (THROTTLED "Similar to
//   429", ACCESS_DENIED "Similar to 401", INTERNAL_SERVER_ERROR; the API "can
//   return a 200 OK response code in cases that would typically produce 4xx
//   or 5xx errors").
// - Rate limits: https://shopify.dev/docs/apps/build/apis/graphql-admin/rate-limits
//   (extensions.cost.throttleStatus {currentlyAvailable, restoreRate};
//   "Before execution begins, an app's bucket must have enough capacity for
//   the requested cost of a query", so a THROTTLED request did not run and
//   is safe to resend, even a mutation) and
//   https://shopify.dev/docs/api/usage/limits ("The recommended backoff time
//   is one second").

import { ConfigError, UpstreamError } from './errors.js';

const USER_AGENT = 'fresh-market-server/1.0';

/** Module-scope cache, reused while the Vercel instance stays warm. */
const tokenState = { token: '', expiresAt: 0, inflight: /** @type {Promise<string>|null} */ (null) };

export function resetAdminTokenCache() {
  tokenState.token = '';
  tokenState.expiresAt = 0;
  tokenState.inflight = null;
}

/**
 * @typedef {object} Ctx
 * @property {import('./config.js').Config} config
 * @property {typeof fetch} fetch
 * @property {() => number} now           ms since epoch
 * @property {(ms: number) => Promise<void>} sleep
 * @property {number} deadline            ms since epoch; no waits past it
 * @property {{shopifyCalls: number}} stats
 */

/**
 * @param {Ctx} ctx
 * @param {{force?: boolean}} [opts]
 */
export async function getAdminToken(ctx, { force = false } = {}) {
  const { config } = ctx;
  if (config.adminToken) return config.adminToken;
  if (!config.clientId || !config.clientSecret) {
    throw new ConfigError('Set SHOPIFY_CLIENT_ID and SHOPIFY_CLIENT_SECRET (or the legacy SHOPIFY_ADMIN_TOKEN).');
  }
  if (!force && tokenState.token && ctx.now() < tokenState.expiresAt - 60_000) return tokenState.token;
  if (!force && tokenState.inflight) return tokenState.inflight;
  const pending = requestToken(ctx).finally(() => {
    if (tokenState.inflight === pending) tokenState.inflight = null;
  });
  tokenState.inflight = pending;
  return pending;
}

/** @param {Ctx} ctx */
async function requestToken(ctx) {
  const { config } = ctx;
  let res;
  try {
    ctx.stats.shopifyCalls++;
    res = await ctx.fetch(`https://${config.storeDomain}/admin/oauth/access_token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        Accept: 'application/json',
        'User-Agent': USER_AGENT,
      },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: config.clientId,
        client_secret: config.clientSecret,
      }).toString(),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    throw new UpstreamError(`Admin token request failed: ${errName(err)}`);
  }
  if (res.status === 429 || res.status >= 500) {
    throw new UpstreamError(`Admin token request HTTP ${res.status}`, { retryAfterSeconds: retryAfter(res) });
  }
  let body = null;
  try {
    body = await res.json();
  } catch {
    /* handled below */
  }
  if (!res.ok || typeof body?.access_token !== 'string') {
    // Shopify's OAuth error code (for example shop_not_permitted) holds no secret.
    const code = typeof body?.error === 'string' ? body.error.slice(0, 60) : 'no_token';
    throw new ConfigError(`Shopify refused the app credentials (HTTP ${res.status}, ${code}).`);
  }
  const expiresIn = Number.isFinite(body.expires_in) ? body.expires_in : 86_399;
  tokenState.token = body.access_token;
  tokenState.expiresAt = ctx.now() + expiresIn * 1000;
  return tokenState.token;
}

/**
 * Runs one GraphQL Admin request and returns `data`.
 *
 * Retries: THROTTLED (HTTP 200 or 429) is always resent after the wait
 * Shopify's cost data asks for. Network errors and 5xx are resent only for
 * reads (`mutation: false`), because a mutation that timed out may have run.
 * A 401 or ACCESS_DENIED gets one fresh client-credentials token.
 *
 * @param {Ctx} ctx
 * @param {string} query
 * @param {Record<string, unknown>} [variables]
 * @param {{mutation?: boolean, label?: string}} [opts]
 */
export async function adminGraphql(ctx, query, variables = {}, { mutation = false, label = 'admin' } = {}) {
  const { config } = ctx;
  const url = `https://${config.storeDomain}/admin/api/${config.apiVersion}/graphql.json`;
  const maxAttempts = 3;
  let refreshed = false;
  for (let attempt = 1; ; attempt++) {
    const last = attempt >= maxAttempts;
    const token = await getAdminToken(ctx);
    let res;
    try {
      ctx.stats.shopifyCalls++;
      res = await ctx.fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-Shopify-Access-Token': token,
          'User-Agent': USER_AGENT,
        },
        body: JSON.stringify({ query, variables }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch (err) {
      if (!mutation && !last && (await backoff(ctx, attempt))) continue;
      throw new UpstreamError(`${label}: network error ${errName(err)}`);
    }

    if (res.status === 401 || res.status === 403) {
      if (res.status === 401 && !refreshed && !config.adminToken) {
        refreshed = true;
        await getAdminToken(ctx, { force: true });
        continue;
      }
      throw new ConfigError(`${label}: Shopify Admin API answered HTTP ${res.status}; check the app install and scopes.`);
    }
    if (res.status === 429) {
      const wait = retryAfter(res) ?? 1;
      if (!last && (await waitFor(ctx, wait * 1000))) continue;
      throw new UpstreamError(`${label}: HTTP 429`, { kind: 'throttled', retryAfterSeconds: wait });
    }
    if (res.status >= 500) {
      if (!mutation && !last && (await backoff(ctx, attempt))) continue;
      throw new UpstreamError(`${label}: HTTP ${res.status}`);
    }
    if (!res.ok) {
      // 400 bad request, 402 frozen, 404, 423 locked: retrying will not help.
      throw new UpstreamError(`${label}: HTTP ${res.status}`, { retryable: false });
    }

    let body;
    try {
      body = await res.json();
    } catch {
      if (!mutation && !last && (await backoff(ctx, attempt))) continue;
      throw new UpstreamError(`${label}: response was not JSON`);
    }

    const errors = Array.isArray(body?.errors) ? body.errors : body?.errors ? [body.errors] : [];
    if (errors.length) {
      const codes = errors.map((e) => e?.extensions?.code).filter(Boolean);
      if (codes.includes('THROTTLED')) {
        const wait = throttleWaitMs(body?.extensions?.cost);
        if (!last && (await waitFor(ctx, wait))) continue;
        throw new UpstreamError(`${label}: THROTTLED`, { kind: 'throttled', retryAfterSeconds: Math.ceil(wait / 1000) });
      }
      if (codes.includes('ACCESS_DENIED')) {
        if (!refreshed && !config.adminToken) {
          refreshed = true;
          await getAdminToken(ctx, { force: true });
          continue;
        }
        throw new ConfigError(`${label}: ACCESS_DENIED (${firstMessage(errors)}); check the app's access scopes.`);
      }
      if (codes.includes('INTERNAL_SERVER_ERROR')) {
        if (!mutation && !last && (await backoff(ctx, attempt))) continue;
        throw new UpstreamError(`${label}: INTERNAL_SERVER_ERROR`);
      }
      if (codes.includes('SHOP_INACTIVE')) {
        throw new UpstreamError(`${label}: SHOP_INACTIVE`, { retryable: false });
      }
      // A schema or query error is this server's bug, not the customer's.
      throw new ConfigError(`${label}: GraphQL error ${codes.join(',') || ''} ${firstMessage(errors)}`.trim());
    }
    if (!body || typeof body.data !== 'object' || body.data === null) {
      throw new UpstreamError(`${label}: response had no data`);
    }
    return body.data;
  }
}

function firstMessage(errors) {
  const m = errors[0]?.message;
  return typeof m === 'string' ? m.slice(0, 200) : '';
}

function errName(err) {
  return err instanceof Error ? err.name : 'error';
}

/** Seconds from a Retry-After header, or undefined. */
export function retryAfter(res) {
  const v = Number(res.headers?.get?.('retry-after'));
  return Number.isFinite(v) && v > 0 ? Math.min(v, 60) : undefined;
}

/**
 * How long until the bucket holds the requested cost again: (requested -
 * available) / restoreRate seconds, at least the documented one second.
 */
export function throttleWaitMs(cost) {
  const status = cost?.throttleStatus;
  const requested = Number(cost?.requestedQueryCost);
  const available = Number(status?.currentlyAvailable);
  const rate = Number(status?.restoreRate);
  let seconds = 1;
  if (Number.isFinite(requested) && Number.isFinite(available) && Number.isFinite(rate) && rate > 0) {
    seconds = Math.max(1, (requested - available) / rate);
  }
  return Math.min(Math.ceil(seconds * 1000), 5_000);
}

async function backoff(ctx, attempt) {
  return waitFor(ctx, 300 * 2 ** (attempt - 1));
}

/** Sleeps when the wait still fits before the request deadline. */
async function waitFor(ctx, ms) {
  if (ctx.now() + ms > ctx.deadline) return false;
  await ctx.sleep(ms);
  return true;
}
