// POST /api/orders: turns the app's basket into a real Shopify order, paid
// cash on delivery.
//
// How (see README "How an order is made" and the research brief):
// draftOrderCreate with paymentTerms set to the "Due on fulfillment"
// template, then draftOrderComplete. The deprecated paymentPending argument
// is not used: its deprecation reason reads "Create a draft with payment
// terms rather than marking the draft as pending."
//
// Docs relied on (copies in server_docs/):
// - draftOrderCreate / DraftOrderInput (purchasingEntity, email,
//   presentmentCurrencyCode, acceptAutomaticDiscounts, lineItems "Accepts a
//   maximum of 499 line items", shippingLine, shippingAddress,
//   billingAddress, note, tags, customAttributes, paymentTerms);
//   https://shopify.dev/docs/api/admin-graphql/2026-10/input-objects/DraftOrderInput
// - ShippingLineInput: "A custom shipping line includes a title and price";
//   priceWithCurrency "If provided, `price` will be ignored."
// - MailingAddressInput: countryCode, provinceCode, phone "Formatted using
//   E.164 standard".
// - PaymentTermsInput.paymentTermsTemplateId; paymentTermsTemplates(
//   paymentTermsType: FULFILLMENT); PaymentTermsType.FULFILLMENT "due on
//   fulfillment".
// - DraftOrder.ready "Whether the draft order is ready and can be
//   completed. Draft orders might have asynchronous operations that can take
//   time to finish."
// - draftOrderComplete: "When completing a draft order, inventory is
//   committed ... Make sure to verify inventory availability before
//   completing the draft order."
// - draftOrderDelete(input: {id}) { deletedId }.
// - draftOrders / orders search: tag, customer_id, status, created_at
//   filters; "If you specify an invalid field, then the query is ignored and
//   all results are returned" (https://shopify.dev/docs/api/usage/search-syntax),
//   so every search result is re-checked here.
// - customerByIdentifier(identifier: {emailAddress}) "Requires
//   `read_customers`".

import { adminGraphql } from './shopify-admin.js';
import { verifyCustomer } from './shopify-customer.js';
import { ApiError, ConfigError, UpstreamError, rateLimited, validationError } from './errors.js';
import { buildQuote, variantsFromData, VARIANT_FIELDS } from './quote.js';
import { MODE_LABEL, SHIPPING_TITLE, placeLabel, provinceCode } from './delivery.js';
import { decimalToFils, filsToDecimal, formatAed } from './money.js';
import { parseOrderBody } from './validate.js';

export const PAYMENT_METHOD = 'Cash on Delivery';
export const SOURCE = 'Fresh Market app';

const termsCache = { id: '' };
export function resetOrderCaches() {
  termsCache.id = '';
}

const MONEY = 'shopMoney { amount }';

export const PREPARE_QUERY = `query FreshMarketPrepare($ids: [ID!]!, $idem: String!, $recent: String!, $recentDrafts: String!, $recentFirst: Int!, $wantTerms: Boolean!) {
  shop { currencyCode }
  nodes(ids: $ids) { ... on ProductVariant {${VARIANT_FIELDS}
  } }
  idemDrafts: draftOrders(first: 5, query: $idem) {
    nodes { id status tags customer { id } customAttributes { key value }
      order { id name totalPriceSet { ${MONEY} } customAttributes { key value } } }
  }
  idemOrders: orders(first: 3, query: $idem) {
    nodes { id name tags customer { id } totalPriceSet { ${MONEY} } customAttributes { key value } }
  }
  recentOrders: orders(first: $recentFirst, sortKey: CREATED_AT, reverse: true, query: $recent) {
    nodes { id createdAt customer { id } }
  }
  recentDrafts: draftOrders(first: $recentFirst, sortKey: ID, reverse: true, query: $recentDrafts) {
    nodes { id status createdAt tags customer { id } }
  }
  paymentTermsTemplates(paymentTermsType: FULFILLMENT) @include(if: $wantTerms) { id name paymentTermsType }
}`;

export const CREATE_MUTATION = `mutation FreshMarketDraftCreate($input: DraftOrderInput!) {
  draftOrderCreate(input: $input) {
    draftOrder { id name ready status }
    userErrors { field message }
  }
}`;

export const STATE_QUERY = `query FreshMarketDraftState($id: ID!, $idem: String!, $lineFirst: Int!) {
  draftOrder(id: $id) {
    id ready status taxesIncluded
    totalPriceSet { ${MONEY} }
    lineItems(first: $lineFirst) { nodes { variant { id } quantity originalUnitPriceSet { ${MONEY} } } }
    order { id name totalPriceSet { ${MONEY} } }
  }
  draftOrders(first: 5, query: $idem) { nodes { id status tags customer { id } } }
}`;

export const WINNER_QUERY = `query FreshMarketDraftWinner($id: ID!) {
  draftOrder(id: $id) { id status customAttributes { key value } order { id name totalPriceSet { ${MONEY} } customAttributes { key value } } }
}`;

export const COMPLETE_MUTATION = `mutation FreshMarketDraftComplete($id: ID!) {
  draftOrderComplete(id: $id) {
    draftOrder { id status order { id name displayFinancialStatus totalPriceSet { ${MONEY} } } }
    userErrors { field message }
  }
}`;

export const DELETE_MUTATION = `mutation FreshMarketDraftDelete($input: DraftOrderDeleteInput!) {
  draftOrderDelete(input: $input) { deletedId userErrors { field message } }
}`;

export const CUSTOMER_BY_EMAIL_QUERY = `query FreshMarketCustomerByEmail($email: String!) {
  customerByIdentifier(identifier: { emailAddress: $email }) { id }
}`;

/**
 * @param {import('./shopify-admin.js').Ctx & {log: (f: Record<string, unknown>) => void}} ctx
 * @param {{token: string, idemKey: string, body: unknown, logFields: Record<string, unknown>}} req
 * @returns {Promise<{status: number, body: Record<string, unknown>, headers?: Record<string, string>}>}
 */
export async function placeOrder(ctx, { token, idemKey, body, logFields }) {
  const { config } = ctx;
  const input = parseOrderBody(body, config);
  if (input.errors.length) throw validationError(input.errors);

  const customer = await verifyCustomer(ctx, token);
  logFields.customer = customer.numericId;

  const nowMs = ctx.now();
  const since = new Date(nowMs - 3600_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const tag = `idem-${idemKey}`;
  const idemQuery = `tag:"${tag}"`;
  const data = await adminGraphql(
    ctx,
    PREPARE_QUERY,
    {
      ids: input.lines.map((l) => l.gid),
      idem: idemQuery,
      recent: `customer_id:${customer.numericId} created_at:>='${since}'`,
      recentDrafts: `customer_id:${customer.numericId} status:open tag:app created_at:>='${since}'`,
      recentFirst: config.maxOrdersPerHour + 1,
      wantTerms: !config.paymentTermsTemplateId && !termsCache.id,
    },
    { label: 'prepare' },
  );
  const variants = variantsFromData(data);

  // 1. Same Idempotency-Key seen before?
  const existing = findExisting(data, tag, customer.id);
  if (existing.otherCustomer) {
    throw validationError([{ field: 'Idempotency-Key', message: 'This Idempotency-Key was already used. Send a new one for a new order.' }]);
  }
  if (existing.order) {
    logFields.outcome = 'replay';
    return replay(existing.order);
  }

  // 2. Per-customer limit (a retry that resumes its own draft is not a new order).
  if (!existing.openDraftId) {
    const recent = countRecent(data, customer.id, Date.parse(since));
    if (recent.count >= config.maxOrdersPerHour) {
      const retry = recent.oldestMs ? Math.max(60, Math.ceil((recent.oldestMs + 3600_000 - nowMs) / 1000)) : 3600;
      logFields.outcome = 'limited';
      throw rateLimited(retry, `You can place at most ${config.maxOrdersPerHour} orders an hour. Please try again later.`);
    }
  }

  // 3. Fresh quote from Shopify's prices and stock.
  const now = new Date(nowMs);
  const quote = buildQuote({ lines: input.lines, delivery: input.delivery, variants, config, now });
  const problems = [...quote.problems];
  if (input.expectedTotalFils !== undefined && input.expectedTotalFils !== quote.totalFils && !problems.length) {
    problems.push({
      variantId: null,
      kind: 'price_changed',
      message: `Your total changed from ${formatAed(input.expectedTotalFils)} to ${formatAed(quote.totalFils)}.`,
    });
  }
  if (problems.length) {
    if (existing.openDraftId) await deleteDraft(ctx, existing.openDraftId);
    logFields.outcome = 'quote_changed';
    return { status: 409, body: { error: 'quote_changed', message: problems[0].message, problems, quote } };
  }
  if (quote.subtotalFils < config.minOrderFils) {
    if (existing.openDraftId) await deleteDraft(ctx, existing.openDraftId);
    throw validationError([{ field: 'lines', message: `The minimum order is ${formatAed(config.minOrderFils)}. Add ${formatAed(config.minOrderFils - quote.subtotalFils)} more.` }]);
  }

  const termsId = config.paymentTermsTemplateId || termsCache.id || pickTermsTemplate(data);
  termsCache.id = config.paymentTermsTemplateId ? '' : termsId;

  const promise = quote.deliveryPromise;
  const lineFirst = Math.max(1, Math.min(100, input.lines.length));

  // 4. Resume an open draft left by an earlier attempt with this key, if it still matches.
  let draftId = '';
  if (existing.openDraftId) {
    const state = await draftState(ctx, existing.openDraftId, idemQuery, lineFirst);
    if (state && state.status === 'OPEN' && sameLines(state, quote)) {
      draftId = existing.openDraftId;
      logFields.resumed = true;
    } else {
      await deleteDraft(ctx, existing.openDraftId);
    }
  }

  // 5. Create the draft.
  if (!draftId) {
    const draftInput = buildDraftInput({ customerId: customer.id, email: customer.email, input, quote, tag, promise, termsId });
    draftId = await createDraft(ctx, draftInput, customer);
  }
  logFields.draft = numericId(draftId);

  // 6. Wait until Shopify has finished calculating; settle duplicate drafts.
  const state = await waitReady(ctx, { draftId, tag, idemQuery, lineFirst, customerId: customer.id, logFields });
  if (state.replay) {
    logFields.outcome = 'replay';
    return state.replay;
  }
  if (state.completed) {
    // A parallel retry with this key completed this very draft.
    logFields.outcome = 'replay';
    return created(state.completed, promise, quote.totalFils);
  }

  // 7. Shopify's totals must equal the quote the customer accepted.
  const mismatch = compareDraft(state.draft, quote);
  if (mismatch) {
    await deleteDraft(ctx, draftId);
    if (state.draft.taxesIncluded === false) {
      throw new ConfigError('Shopify calculated tax on top of prices. Turn on "Include sales tax in product price and shipping rate" in Settings > Taxes and duties.');
    }
    logFields.outcome = 'total_mismatch';
    return { status: 409, body: { error: 'quote_changed', message: mismatch[0].message, problems: mismatch, quote } };
  }

  // 8. Complete: the draft becomes a real order, payment due on fulfillment.
  const order = await completeDraft(ctx, draftId);
  logFields.order = order.name;
  logFields.financialStatus = order.displayFinancialStatus;
  logFields.outcome = 'created';
  return created(order, promise, quote.totalFils);
}

function created(order, promise, fallbackTotal) {
  return {
    status: 201,
    body: {
      orderId: order.id,
      orderName: order.name,
      totalFils: decimalToFils(order.totalPriceSet?.shopMoney?.amount) ?? fallbackTotal,
      deliveryPromise: promise,
      paymentMethod: PAYMENT_METHOD,
    },
  };
}

/** Finds an order or draft already made with this key. */
export function findExisting(data, tag, customerId) {
  const out = { order: null, openDraftId: '', otherCustomer: false };
  const drafts = (data?.idemDrafts?.nodes ?? []).filter((d) => Array.isArray(d?.tags) && d.tags.includes(tag));
  const orders = (data?.idemOrders?.nodes ?? []).filter((o) => Array.isArray(o?.tags) && o.tags.includes(tag));
  for (const x of [...drafts, ...orders]) {
    if (x.customer?.id && x.customer.id !== customerId) out.otherCustomer = true;
  }
  if (out.otherCustomer) return out;
  const done = drafts.find((d) => d.status === 'COMPLETED' && d.order?.id);
  if (done) {
    out.order = { ...done.order, customAttributes: done.order.customAttributes ?? done.customAttributes };
    return out;
  }
  if (orders[0]) {
    out.order = orders[0];
    return out;
  }
  const open = drafts.filter((d) => d.status === 'OPEN').sort(byNumericId);
  if (open[0]) out.openDraftId = open[0].id;
  return out;
}

function countRecent(data, customerId, sinceMs) {
  const times = [];
  for (const o of data?.recentOrders?.nodes ?? []) {
    const t = Date.parse(o?.createdAt);
    if (o?.customer?.id === customerId && t >= sinceMs) times.push(t);
  }
  for (const d of data?.recentDrafts?.nodes ?? []) {
    const t = Date.parse(d?.createdAt);
    if (d?.status === 'OPEN' && d?.customer?.id === customerId && Array.isArray(d.tags) && d.tags.includes('app') && t >= sinceMs) times.push(t);
  }
  return { count: times.length, oldestMs: times.length ? Math.min(...times) : 0 };
}

function pickTermsTemplate(data) {
  const t = (data?.paymentTermsTemplates ?? []).find((x) => x?.paymentTermsType === 'FULFILLMENT' && typeof x.id === 'string');
  if (!t) throw new ConfigError('No "Due on fulfillment" payment terms template was found (paymentTermsTemplates).');
  return t.id;
}

function attr(list, key) {
  const hit = (list ?? []).find((a) => a?.key === key);
  return typeof hit?.value === 'string' ? hit.value : '';
}

function replay(order) {
  return {
    status: 201,
    headers: { 'Idempotent-Replayed': 'true' },
    body: {
      orderId: order.id,
      orderName: order.name,
      totalFils: decimalToFils(order.totalPriceSet?.shopMoney?.amount) ?? 0,
      deliveryPromise: attr(order.customAttributes, 'Delivery promise'),
      paymentMethod: PAYMENT_METHOD,
    },
  };
}

/** The DraftOrderInput for this order. */
export function buildDraftInput({ customerId, email, input, quote, tag, promise, termsId }) {
  const { delivery, address } = input;
  const mailing = {
    firstName: address.firstName,
    lastName: address.lastName,
    address1: address.address1,
    ...(address.address2 ? { address2: address.address2 } : {}),
    city: address.city,
    provinceCode: provinceCode(address.emirate),
    countryCode: 'AE',
    phone: address.phone,
  };
  const attributes = [
    { key: 'Delivery mode', value: MODE_LABEL[delivery.mode] },
    { key: 'Delivery area', value: placeLabel(delivery.area.name, delivery.area.emirate) },
    { key: 'Delivery promise', value: promise },
    { key: 'Delivery pin', value: delivery.pin },
  ];
  if (input.instructions) attributes.push({ key: 'Delivery instructions', value: input.instructions });
  attributes.push({ key: 'Source', value: SOURCE }, { key: 'Payment method', value: PAYMENT_METHOD });

  return {
    purchasingEntity: { customerId },
    ...(email ? { email } : {}),
    presentmentCurrencyCode: 'AED',
    acceptAutomaticDiscounts: false,
    lineItems: quote.lines.filter((l) => l.available).map((l) => ({
      variantId: input.lines.find((x) => x.variantId === l.variantId).gid,
      quantity: l.quantity,
    })),
    shippingLine: {
      title: SHIPPING_TITLE[delivery.mode],
      priceWithCurrency: { amount: filsToDecimal(quote.deliveryFeeFils), currencyCode: 'AED' },
    },
    shippingAddress: mailing,
    billingAddress: mailing,
    ...(input.note ? { note: input.note } : {}),
    tags: ['app', 'cod', tag],
    customAttributes: attributes,
    paymentTerms: { paymentTermsTemplateId: termsId },
  };
}

async function createDraft(ctx, draftInput, customer) {
  let res = await adminGraphql(ctx, CREATE_MUTATION, { input: draftInput }, { mutation: true, label: 'draftOrderCreate' });
  let payload = res?.draftOrderCreate;
  if (payload?.userErrors?.length && isCustomerError(payload.userErrors) && customer.email) {
    // The Customer Account API id should be the Admin customer id; if Shopify
    // disagrees, look the customer up by the verified email once.
    const found = await adminGraphql(ctx, CUSTOMER_BY_EMAIL_QUERY, { email: customer.email }, { label: 'customerByIdentifier' });
    const adminId = found?.customerByIdentifier?.id;
    if (typeof adminId === 'string' && adminId !== customer.id) {
      res = await adminGraphql(ctx, CREATE_MUTATION, { input: { ...draftInput, purchasingEntity: { customerId: adminId } } }, { mutation: true, label: 'draftOrderCreate' });
      payload = res?.draftOrderCreate;
    }
  }
  if (payload?.userErrors?.length) {
    if (isCustomerError(payload.userErrors)) {
      throw new ConfigError(`draftOrderCreate rejected the customer: ${payload.userErrors[0].message}`);
    }
    throw validationError(payload.userErrors.map(mapUserError));
  }
  const id = payload?.draftOrder?.id;
  if (typeof id !== 'string') throw new UpstreamError('draftOrderCreate returned no draft');
  return id;
}

function isCustomerError(errors) {
  return errors.some((e) => {
    const path = Array.isArray(e?.field) ? e.field.join('.') : '';
    return /purchasingEntity|customerId/.test(path);
  });
}

/** Shopify's input path -> the app's field name. */
export function mapUserError(e) {
  const path = Array.isArray(e?.field) ? e.field.filter((p) => p !== 'input') : [];
  const message = typeof e?.message === 'string' ? e.message : 'Shopify did not accept the order.';
  const [head, second, third] = path;
  if (head === 'shippingAddress' || head === 'billingAddress') {
    if (second === 'provinceCode' || second === 'countryCode') return { field: 'address.emirate', message };
    return { field: second ? `address.${second}` : 'address', message };
  }
  if (head === 'lineItems') {
    return { field: second !== undefined ? `lines[${second}]${third === 'quantity' ? '.quantity' : ''}` : 'lines', message };
  }
  if (head === 'note') return { field: 'note', message };
  if (head === 'customAttributes') return { field: 'instructions', message };
  if (head === 'shippingLine') return { field: 'delivery', message };
  return { field: 'order', message };
}

async function draftState(ctx, id, idemQuery, lineFirst) {
  const data = await adminGraphql(ctx, STATE_QUERY, { id, idem: idemQuery, lineFirst }, { label: 'draftState' });
  return data?.draftOrder ? { ...data.draftOrder, siblings: data.draftOrders?.nodes ?? [] } : null;
}

function sameLines(state, quote) {
  const want = new Map(quote.lines.filter((l) => l.available).map((l) => [String(l.variantId).replace(/^gid:\/\/shopify\/ProductVariant\//, ''), l.quantity]));
  const got = state.lineItems?.nodes ?? [];
  if (got.length !== want.size) return false;
  for (const li of got) {
    const id = numericId(li?.variant?.id ?? '');
    if (want.get(id) !== li.quantity) return false;
  }
  return decimalToFils(state.totalPriceSet?.shopMoney?.amount) === quote.totalFils;
}

/**
 * Polls `ready` and settles a race between two requests with the same key:
 * the draft with the lowest id wins; the other deletes itself and reports
 * the winner's order once it exists.
 */
async function waitReady(ctx, { draftId, tag, idemQuery, lineFirst, customerId, logFields }) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const state = await draftState(ctx, draftId, idemQuery, lineFirst);
    if (!state) throw new UpstreamError('Draft order disappeared before completion');
    const rivals = state.siblings
      .filter((d) => d?.id !== draftId && Array.isArray(d?.tags) && d.tags.includes(tag) && d.customer?.id === customerId)
      .filter((d) => d.status === 'COMPLETED' || (d.status === 'OPEN' && byNumericId(d, { id: draftId }) < 0));
    if (rivals.length) {
      logFields.duplicate = true;
      await deleteDraft(ctx, draftId);
      const winner = await waitForWinner(ctx, rivals.sort(byNumericId)[0].id);
      if (winner) return { replay: replay(winner) };
      throw new UpstreamError('A duplicate request for this order is still running');
    }
    if (state.status === 'COMPLETED' && state.order?.id) return { completed: state.order };
    if (state.ready) return { draft: state };
    if (!(await pause(ctx, 400 + attempt * 200))) break;
  }
  throw new UpstreamError('The draft order did not become ready in time');
}

async function waitForWinner(ctx, id) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const data = await adminGraphql(ctx, WINNER_QUERY, { id }, { label: 'draftWinner' });
    const d = data?.draftOrder;
    if (d?.status === 'COMPLETED' && d.order?.id) {
      return { ...d.order, customAttributes: d.order.customAttributes ?? d.customAttributes };
    }
    if (!d) return null;
    if (!(await pause(ctx, 500))) break;
  }
  return null;
}

/** null when the draft matches the quote, else the problems to show. */
export function compareDraft(draft, quote) {
  const problems = [];
  const byId = new Map((draft.lineItems?.nodes ?? []).map((li) => [numericId(li?.variant?.id ?? ''), li]));
  for (const l of quote.lines) {
    if (!l.available) continue;
    const li = byId.get(String(l.variantId).replace(/^gid:\/\/shopify\/ProductVariant\//, ''));
    const unit = decimalToFils(li?.originalUnitPriceSet?.shopMoney?.amount);
    if (unit !== null && unit !== l.unitPriceFils) {
      problems.push({
        variantId: l.variantId,
        kind: 'price_changed',
        message: `The price of ${l.title || 'an item'} changed from ${formatAed(l.unitPriceFils)} to ${formatAed(unit)}.`,
      });
    }
  }
  const total = decimalToFils(draft.totalPriceSet?.shopMoney?.amount);
  if (total !== quote.totalFils && !problems.length) {
    problems.push({
      variantId: null,
      kind: 'price_changed',
      message: `Your total changed from ${formatAed(quote.totalFils)} to ${formatAed(total ?? 0)}.`,
    });
  }
  return problems.length ? problems : null;
}

async function completeDraft(ctx, id) {
  const data = await adminGraphql(ctx, COMPLETE_MUTATION, { id }, { mutation: true, label: 'draftOrderComplete' });
  const payload = data?.draftOrderComplete;
  const order = payload?.draftOrder?.order;
  if (order?.id) return order;
  if (payload?.userErrors?.length) {
    // Already completed by a parallel retry?
    const check = await adminGraphql(ctx, WINNER_QUERY, { id }, { label: 'draftWinner' });
    if (check?.draftOrder?.status === 'COMPLETED' && check.draftOrder.order?.id) return check.draftOrder.order;
    await deleteDraft(ctx, id);
    const detail = String(payload.userErrors[0]?.message ?? '').slice(0, 200);
    throw new ApiError(422, 'invalid', 'We could not place the order. Please check your basket and try again.', { field: 'order', detail, errors: [{ field: 'order', message: detail }] });
  }
  throw new UpstreamError('draftOrderComplete returned no order');
}

async function deleteDraft(ctx, id) {
  try {
    await adminGraphql(ctx, DELETE_MUTATION, { input: { id } }, { mutation: true, label: 'draftOrderDelete' });
  } catch (err) {
    // Best effort: an orphan draft is harmless (never charged, auto-deleted after a year of inactivity).
    ctx.log?.({ event: 'draft_delete_failed', draft: numericId(id), reason: err instanceof Error ? err.name : 'error' });
  }
}

async function pause(ctx, ms) {
  if (ctx.now() + ms > ctx.deadline) return false;
  await ctx.sleep(ms);
  return true;
}

function numericId(gid) {
  const m = /(\d+)$/.exec(String(gid));
  return m ? m[1] : '';
}

function byNumericId(a, b) {
  const x = BigInt(numericId(a.id) || '0');
  const y = BigInt(numericId(b.id) || '0');
  return x < y ? -1 : x > y ? 1 : 0;
}
