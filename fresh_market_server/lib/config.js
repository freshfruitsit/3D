// Reads the server's settings from environment variables. Secrets
// (SHOPIFY_CLIENT_SECRET, SHOPIFY_ADMIN_TOKEN) are only ever read here and
// passed to the Shopify client; they are never logged or returned.

import { ConfigError } from './errors.js';
import { decimalToFils } from './money.js';

/** "2026-10" is the latest stable version (https://shopify.dev/docs/api/usage/versioning). */
export const DEFAULT_API_VERSION = '2026-10';

/**
 * @typedef {object} Config
 * @property {string} storeDomain        testtfm.myshopify.com
 * @property {string} apiVersion         2026-10
 * @property {string} shopId             79173124173 ('' when unset)
 * @property {string} adminToken         legacy override ('' when unset)
 * @property {string} clientId           Dev Dashboard app client ID
 * @property {string} clientSecret       Dev Dashboard app client secret
 * @property {number} deliveryFeeFils
 * @property {number} freeDeliveryFromFils
 * @property {number} minOrderFils
 * @property {number} maxLines
 * @property {number} maxQtyPerLine
 * @property {number} maxOrdersPerHour
 * @property {string} customerApiUrl     override for the discovered endpoint ('' = discover)
 * @property {string} paymentTermsTemplateId override ('' = look it up)
 */

/**
 * @param {Record<string, string|undefined>} [env]
 * @returns {Config}
 */
export function loadConfig(env = process.env) {
  const bad = [];
  const str = (name) => (env[name] ?? '').trim();

  const storeDomain = str('SHOPIFY_STORE_DOMAIN').toLowerCase();
  if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(storeDomain)) bad.push('SHOPIFY_STORE_DOMAIN');

  const apiVersion = str('SHOPIFY_API_VERSION') || DEFAULT_API_VERSION;
  if (!/^\d{4}-(01|04|07|10)$/.test(apiVersion)) bad.push('SHOPIFY_API_VERSION');

  const shopId = str('SHOPIFY_SHOP_ID');
  if (shopId && !/^\d{1,20}$/.test(shopId)) bad.push('SHOPIFY_SHOP_ID');

  const aed = (name, fallback) => {
    const raw = str(name) || fallback;
    const fils = decimalToFils(raw);
    if (fils === null || fils < 0) {
      bad.push(name);
      return 0;
    }
    return fils;
  };
  const int = (name, fallback, min, max) => {
    const raw = str(name);
    if (!raw) return fallback;
    const n = Number(raw);
    if (!Number.isInteger(n) || n < min || n > max) {
      bad.push(name);
      return fallback;
    }
    return n;
  };

  const customerApiUrl = str('CUSTOMER_ACCOUNT_API_URL');
  if (customerApiUrl && !/^https:\/\/[^\s/]+\/\S+$/.test(customerApiUrl)) bad.push('CUSTOMER_ACCOUNT_API_URL');

  const paymentTermsTemplateId = str('SHOPIFY_PAYMENT_TERMS_TEMPLATE_ID');
  if (paymentTermsTemplateId && !/^gid:\/\/shopify\/PaymentTermsTemplate\/\d+$/.test(paymentTermsTemplateId)) {
    bad.push('SHOPIFY_PAYMENT_TERMS_TEMPLATE_ID');
  }

  const config = {
    storeDomain,
    apiVersion,
    shopId,
    adminToken: str('SHOPIFY_ADMIN_TOKEN'),
    clientId: str('SHOPIFY_CLIENT_ID'),
    clientSecret: str('SHOPIFY_CLIENT_SECRET'),
    deliveryFeeFils: aed('DELIVERY_FEE_AED', '25'),
    freeDeliveryFromFils: aed('FREE_DELIVERY_FROM_AED', '200'),
    minOrderFils: aed('MIN_ORDER_AED', '0'),
    // lineItems(first: 100) reads them back, and Shopify caps array inputs at 250.
    maxLines: int('MAX_LINES', 50, 1, 100),
    maxQtyPerLine: int('MAX_QTY_PER_LINE', 50, 1, 999),
    maxOrdersPerHour: int('MAX_ORDERS_PER_HOUR', 5, 1, 100),
    customerApiUrl,
    paymentTermsTemplateId,
  };

  if (bad.length) {
    // Names only, never values.
    throw new ConfigError(`Invalid or missing environment variables: ${bad.join(', ')}`);
  }
  return config;
}
