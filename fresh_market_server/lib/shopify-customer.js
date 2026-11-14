// Checks the app's Customer Account API access token by asking Shopify who
// the customer is.
//
// Docs relied on (copies in server_docs/):
// - https://shopify.dev/docs/api/customer/latest (cust_api_overview.md):
//   discover the endpoint with GET https://{shop}/.well-known/customer-account-api
//   and use `graphql_api` "directly (already includes version)"; requests send
//   `Authorization: {access_token}` (no "Bearer" prefix in Shopify's examples);
//   "401 Unauthorized: The client does not have correct authentication
//   credentials"; per-customer limit "Requests above this limit return HTTP
//   `429` with a `THROTTLED` error and a `Retry-After` header"; "Exceeding the
//   cost limit returns `200 OK` with a `THROTTLED` error instead."
// - Customer object (cust_api_customer_2026-10_objects_Customer.md):
//   id, firstName, lastName, emailAddress { emailAddress },
//   phoneNumber { phoneNumber }.
// - Live discovery for testtfm (live_testtfm_well-known_customer-account-api.json):
//   {"graphql_api":"https://shopify.com/79173124173/account/customer/api/2026-10/graphql", ...}

import { createHash } from 'node:crypto';
import { UpstreamError, unauthorized, rateLimited } from './errors.js';

const USER_AGENT = 'fresh-market-server/1.0';
const DISCOVERY_TTL_MS = 60 * 60 * 1000;
const TOKEN_TTL_MS = 60 * 1000;
const TOKEN_CACHE_MAX = 500;

const discovery = { url: '', expiresAt: 0 };
/** sha256(token) -> {customer, expiresAt}. The raw token is never a key. */
const tokenCache = new Map();

export function resetCustomerCaches() {
  discovery.url = '';
  discovery.expiresAt = 0;
  tokenCache.clear();
}

export const CUSTOMER_QUERY = `query FreshMarketWhoAmI {
  customer {
    id
    firstName
    lastName
    emailAddress { emailAddress }
    phoneNumber { phoneNumber }
  }
}`;

/**
 * @typedef {object} Customer
 * @property {string} id         gid://shopify/Customer/N
 * @property {string} numericId  N
 * @property {string} email      '' when Shopify has none (or redacts it)
 * @property {string} phone      '' when none
 * @property {string} firstName
 * @property {string} lastName
 */

/**
 * The Customer Account API GraphQL URL for the shop.
 * @param {import('./shopify-admin.js').Ctx} ctx
 */
export async function customerApiUrl(ctx) {
  const { config } = ctx;
  if (config.customerApiUrl) return config.customerApiUrl;
  if (discovery.url && ctx.now() < discovery.expiresAt) return discovery.url;
  let url = '';
  try {
    ctx.stats.shopifyCalls++;
    const res = await ctx.fetch(`https://${config.storeDomain}/.well-known/customer-account-api`, {
      headers: { Accept: 'application/json', 'User-Agent': USER_AGENT },
      signal: AbortSignal.timeout(5_000),
    });
    if (res.ok) {
      const body = await res.json();
      if (typeof body?.graphql_api === 'string' && /^https:\/\/[^\s/]+\/\S+$/.test(body.graphql_api)) {
        url = body.graphql_api;
      }
    }
  } catch {
    /* fall through */
  }
  if (!url) {
    if (!config.shopId) throw new UpstreamError('Customer Account API discovery failed');
    // The shape the store's live discovery returned on 2026-11-14.
    url = `https://shopify.com/${config.shopId}/account/customer/api/${config.apiVersion}/graphql`;
  }
  discovery.url = url;
  discovery.expiresAt = ctx.now() + DISCOVERY_TTL_MS;
  return url;
}

/**
 * Who the token belongs to. Throws a 401 ApiError when Shopify does not
 * accept it, 429 when the customer is throttled, UpstreamError otherwise.
 * @param {import('./shopify-admin.js').Ctx} ctx
 * @param {string} token raw access token from the app
 * @returns {Promise<Customer>}
 */
export async function verifyCustomer(ctx, token) {
  const key = createHash('sha256').update(token).digest('hex');
  const hit = tokenCache.get(key);
  if (hit && ctx.now() < hit.expiresAt) return hit.customer;
  if (hit) tokenCache.delete(key);

  const url = await customerApiUrl(ctx);
  let res;
  try {
    ctx.stats.shopifyCalls++;
    res = await ctx.fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        Authorization: token,
        'User-Agent': USER_AGENT,
      },
      body: JSON.stringify({ operationName: 'FreshMarketWhoAmI', query: CUSTOMER_QUERY, variables: {} }),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (err) {
    throw new UpstreamError(`Customer Account API network error: ${err instanceof Error ? err.name : 'error'}`);
  }
  if (res.status === 401) throw unauthorized();
  if (res.status === 429) {
    const wait = Number(res.headers.get('retry-after'));
    throw rateLimited(Number.isFinite(wait) && wait > 0 ? wait : 60, 'Too many requests. Please wait a minute and try again.');
  }
  if (res.status >= 500) throw new UpstreamError(`Customer Account API HTTP ${res.status}`);
  if (!res.ok) throw new UpstreamError(`Customer Account API HTTP ${res.status}`, { retryable: false });

  let body;
  try {
    body = await res.json();
  } catch {
    throw new UpstreamError('Customer Account API response was not JSON');
  }
  const errors = Array.isArray(body?.errors) ? body.errors : [];
  const codes = errors.map((e) => e?.extensions?.code).filter(Boolean);
  if (codes.includes('THROTTLED')) {
    throw rateLimited(2, 'Too many requests. Please try again in a moment.');
  }
  const c = body?.data?.customer;
  // Field-level errors (for example a redacted phone) still leave a valid id.
  if (!c || typeof c.id !== 'string') {
    if (codes.some((code) => code === 'UNAUTHORIZED' || code === 'ACCESS_DENIED') || !errors.length || body?.data?.customer === null) {
      throw unauthorized();
    }
    throw new UpstreamError(`Customer Account API errors: ${codes.join(',') || 'unknown'}`);
  }
  const m = /^gid:\/\/shopify\/Customer\/(\d+)$/.exec(c.id);
  if (!m) throw new UpstreamError('Customer Account API returned an unexpected customer id');
  /** @type {Customer} */
  const customer = {
    id: c.id,
    numericId: m[1],
    email: typeof c.emailAddress?.emailAddress === 'string' ? c.emailAddress.emailAddress : '',
    phone: typeof c.phoneNumber?.phoneNumber === 'string' ? c.phoneNumber.phoneNumber : '',
    firstName: typeof c.firstName === 'string' ? c.firstName : '',
    lastName: typeof c.lastName === 'string' ? c.lastName : '',
  };
  if (tokenCache.size >= TOKEN_CACHE_MAX) tokenCache.delete(tokenCache.keys().next().value);
  tokenCache.set(key, { customer, expiresAt: ctx.now() + TOKEN_TTL_MS });
  return customer;
}
