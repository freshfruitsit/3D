// Prices, stock and Express eligibility come from Shopify, never from the
// app. VAT is included in UAE prices, so total = subtotal + delivery fee.
//
// Fields relied on (https://shopify.dev/docs/api/admin-graphql/2026-10/objects/ProductVariant):
// price "The price of the product variant in the default shop currency";
// availableForSale "Whether the product variant is available for sale";
// inventoryPolicy "Whether customers are allowed to place an order for the
// product variant when it's out of stock" (DENY / CONTINUE);
// inventoryQuantity "The total sellable quantity of the variant";
// InventoryItem.tracked; Product.status (ACTIVE, ARCHIVED, DRAFT, UNLISTED);
// Product.tags; Shop.currencyCode "The three letter code for the currency
// that the shop sells in". nodes(ids:) returns null for unknown ids
// (queries_nodes.md).

import { adminGraphql } from './shopify-admin.js';
import { ConfigError } from './errors.js';
import { decimalToFils, formatAed } from './money.js';
import { deliveryPromise, isExpressTagged } from './delivery.js';

export const VARIANT_FIELDS = `
  id
  title
  price
  availableForSale
  inventoryPolicy
  inventoryQuantity
  inventoryItem { tracked }
  product { title status tags }`;

export const VARIANTS_QUERY = `query FreshMarketVariants($ids: [ID!]!) {
  shop { currencyCode }
  nodes(ids: $ids) { ... on ProductVariant {${VARIANT_FIELDS}
  } }
}`;

/**
 * @param {import('./shopify-admin.js').Ctx} ctx
 * @param {{gid: string}[]} lines
 * @returns {Promise<Map<string, any>>} gid -> variant node (missing when Shopify has none)
 */
export async function fetchVariants(ctx, lines) {
  const data = await adminGraphql(ctx, VARIANTS_QUERY, { ids: lines.map((l) => l.gid) }, { label: 'variants' });
  return variantsFromData(data);
}

/** Reads shop + nodes out of a query result (also used by the order flow). */
export function variantsFromData(data) {
  const currency = data?.shop?.currencyCode;
  if (currency !== 'AED') {
    throw new ConfigError(`The shop currency is ${currency ?? 'unknown'}, but this server prices in AED.`);
  }
  const map = new Map();
  for (const node of data.nodes ?? []) {
    if (node && typeof node.id === 'string') map.set(node.id, node);
  }
  return map;
}

/**
 * @typedef {object} QuoteLine
 * @property {number|string} variantId as the app sent it
 * @property {string} title
 * @property {string} variantTitle
 * @property {number} quantity
 * @property {number} unitPriceFils
 * @property {number} lineTotalFils
 * @property {boolean} available
 */

/**
 * @typedef {object} Problem
 * @property {number|string|null} variantId null when it is about the whole basket
 * @property {'sold_out'|'price_changed'|'not_express'|'qty_reduced'} kind
 * @property {string} message
 */

/**
 * The quote for these lines, from the variants Shopify returned.
 * @param {{
 *   lines: {variantId: number|string, gid: string, quantity: number, unitPriceFils?: number}[],
 *   delivery: {mode: 'market'|'express', area: {name: string, emirate: string, lat: number, lng: number}},
 *   variants: Map<string, any>,
 *   config: import('./config.js').Config,
 *   now: Date,
 * }} input
 */
export function buildQuote({ lines, delivery, variants, config, now }) {
  /** @type {QuoteLine[]} */
  const out = [];
  /** @type {Problem[]} */
  const problems = [];
  let subtotalFils = 0;
  let availableCount = 0;

  for (const line of lines) {
    const v = variants.get(line.gid);
    const title = typeof v?.product?.title === 'string' ? v.product.title : '';
    const variantTitle = typeof v?.title === 'string' ? v.title : '';
    const unit = v ? decimalToFils(v.price) : null;
    const name = title || 'This item';

    const activeProduct = v?.product?.status === 'ACTIVE';
    if (!v || unit === null || !activeProduct || v.availableForSale !== true) {
      out.push({ variantId: line.variantId, title, variantTitle, quantity: line.quantity, unitPriceFils: unit ?? 0, lineTotalFils: 0, available: false });
      problems.push({
        variantId: line.variantId,
        kind: 'sold_out',
        message: v ? `${name} is sold out.` : 'This item is no longer sold.',
      });
      continue;
    }

    let quantity = line.quantity;
    const limited = v.inventoryItem?.tracked === true && v.inventoryPolicy === 'DENY' && Number.isInteger(v.inventoryQuantity);
    if (limited && v.inventoryQuantity < quantity) {
      if (v.inventoryQuantity <= 0) {
        out.push({ variantId: line.variantId, title, variantTitle, quantity: line.quantity, unitPriceFils: unit, lineTotalFils: 0, available: false });
        problems.push({ variantId: line.variantId, kind: 'sold_out', message: `${name} is sold out.` });
        continue;
      }
      quantity = v.inventoryQuantity;
      problems.push({
        variantId: line.variantId,
        kind: 'qty_reduced',
        message: `Only ${quantity} of ${name} left, so we changed ${line.quantity} to ${quantity}.`,
      });
    }

    if (line.unitPriceFils !== undefined && line.unitPriceFils !== unit) {
      problems.push({
        variantId: line.variantId,
        kind: 'price_changed',
        message: `The price of ${name} changed from ${formatAed(line.unitPriceFils)} to ${formatAed(unit)}.`,
      });
    }

    if (delivery.mode === 'express' && !isExpressTagged(v.product?.tags)) {
      problems.push({
        variantId: line.variantId,
        kind: 'not_express',
        message: `${name} isn't on Express. Switch to Fresh Market or remove it.`,
      });
    }

    const lineTotalFils = unit * quantity;
    subtotalFils += lineTotalFils;
    availableCount++;
    out.push({ variantId: line.variantId, title, variantTitle, quantity, unitPriceFils: unit, lineTotalFils, available: true });
  }

  const { promise, expressProblem } = deliveryPromise(delivery.mode, delivery.area, now);
  if (expressProblem) problems.push({ variantId: null, kind: 'not_express', message: expressProblem });

  const deliveryFeeFils = availableCount === 0 || subtotalFils >= config.freeDeliveryFromFils ? 0 : config.deliveryFeeFils;
  return {
    lines: out,
    subtotalFils,
    deliveryFeeFils,
    totalFils: subtotalFils + deliveryFeeFils,
    currency: 'AED',
    deliveryPromise: promise,
    problems,
    minOrderFils: config.minOrderFils,
  };
}
