// POST /api/orders: turns the app's basket into a real Shopify order, paid
// cash on delivery.
//
// How (see README "How an order is made" and the research brief):
// draftOrderCreate with paymentTerms set to the "Due on fulfillment"
// template, then draftOrderComplete. The deprecated paymentPending argument
// is not used: its deprecation reason reads "Create a draft with payment
// terms rather than marking the draft as pending."
//
// One order at a time per customer. Shopify has no idempotency for draft or
// order mutations (the `@idempotent` list in
// https://shopify.dev/docs/apps/build/graphql-admin/implementing-idempotency
// names none), and its search can lag behind new drafts and orders. So the
// server keeps a small lock in an app-owned metafield on the customer
// ($app:checkout, type json) and changes it only with metafieldsSet's
// compare-and-set: "If `compareDigest` is set for any metafield, the mutation
// will only set that metafield if the persisted metafield value matches the
// digest used on `compareDigest`. If the metafield doesn't exist yet, but you
// want to guarantee that the operation will run in a safe manner, set
// `compareDigest` to `null`." (mutations/metafieldsSet; MetafieldsSetUserErrorCode
// STALE_OBJECT "The metafield has been modified since it was loaded."). The
// lock is read by customer id, not searched, and holds:
//   {v, key, owner, until, draftId, orderId, orderName, totalFils, promise,
//    recent: [{id, t}]}
// - key/orderId: the last order's Idempotency-Key and order, so a retry is
//   answered without search;
// - until: while a request holds it, others with the same customer wait,
//   then get 503 retryable; it runs out on its own after LOCK_TTL_MS;
// - draftId: the draft the holder made, so a retry after a crash finishes
//   or replays that very draft;
// - recent: this customer's orders of the last hour, for the hourly limit.
// App-owned metafields use the reserved namespace `$app`
// (https://shopify.dev/docs/apps/build/metafields). metafieldsSet "Requires
// the same access level needed to mutate the owner resource": write_customers.
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
// - customer(id:) and customerByIdentifier(identifier: {emailAddress})
//   "Requires `read_customers`".
// - OrderDisplayFinancialStatus.PENDING: "Orders have this status when ...
//   manual payment methods are being used."
// - tagsAdd(id, tags) on an Order (write_orders).

import { randomUUID } from 'node:crypto';
import { adminGraphql, firstMessage } from './shopify-admin.js';
import { verifyCustomer } from './shopify-customer.js';
import { ApiError, ConfigError, UpstreamError, rateLimited, validationError } from './errors.js';
import { buildQuote, fetchVariants } from './quote.js';
import { MODE_LABEL, SHIPPING_TITLE, placeLabel, provinceCode } from './delivery.js';
import { decimalToFils, filsToDecimal, formatAed } from './money.js';
import { parseOrderBody } from './validate.js';

export const PAYMENT_METHOD = 'Cash on Delivery';
export const SOURCE = 'Fresh Market app';
/** Added to an order that Shopify did not leave payment pending, for staff. */
export const CHECK_PAYMENT_TAG = 'check-payment';

export const LOCK_NAMESPACE = '$app';
export const LOCK_KEY = 'checkout';
/** How long a request may hold the lock. Longer than Vercel's maxDuration (60 s). */
export const LOCK_TTL_MS = 90_000;
/** The holder starts no mutation in the last LOCK_MARGIN_MS of its lock. */
const LOCK_MARGIN_MS = 20_000;
/** While another request holds the lock: wait this long between looks, at most this often. */
const WAIT_POLL_MS = 1_000;
const WAIT_MAX_POLLS = 10;
/** Retry-After for "your order is still being placed". */
const IN_PROGRESS_RETRY_S = 3;

const termsCache = { id: '' };
/** Customer Account API id -> Admin id, only when Shopify says they differ (see placeOrder). */
const adminIdCache = new Map();
export function resetOrderCaches() {
  termsCache.id = '';
  adminIdCache.clear();
}

const MONEY = 'shopMoney { amount }';
const LOCK_FIELDS = `lock: metafield(namespace: "${LOCK_NAMESPACE}", key: "${LOCK_KEY}") { value compareDigest }`;

/** Everything needed before any decision, but not the (larger) variant read. */
export const GATE_QUERY = `query FreshMarketGate($customerId: ID!, $idem: String!, $recent: String!, $recentDrafts: String!, $recentFirst: Int!, $wantTerms: Boolean!) {
  customer(id: $customerId) { id ${LOCK_FIELDS} }
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

export const LOCK_QUERY = `query FreshMarketLock($customerId: ID!) {
  customer(id: $customerId) { id ${LOCK_FIELDS} }
}`;

export const LOCK_SET_MUTATION = `mutation FreshMarketLockSet($metafields: [MetafieldsSetInput!]!) {
  metafieldsSet(metafields: $metafields) {
    metafields { key namespace compareDigest }
    userErrors { field message code }
  }
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
    customAttributes { key value }
    order { id name totalPriceSet { ${MONEY} } customAttributes { key value } }
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

export const TAGS_ADD_MUTATION = `mutation FreshMarketTagsAdd($id: ID!, $tags: [String!]!) {
  tagsAdd(id: $id, tags: $tags) { node { id } userErrors { field message } }
}`;

export const CUSTOMER_BY_EMAIL_QUERY = `query FreshMarketCustomerByEmail($email: String!) {
  customerByIdentifier(identifier: { emailAddress: $email }) { id }
}`;

/**
 * @param {import('./shopify-admin.js').Ctx & {log: (f: Record<string, unknown>) => void, mutationDeadline?: number}} ctx
 * @param {{token: string, idemKey: string, body: unknown, logFields: Record<string, unknown>}} req
 * @returns {Promise<{status: number, body: Record<string, unknown>, headers?: Record<string, string>}>}
 */
export async function placeOrder(ctx, { token, idemKey, body, logFields }) {
  const { config } = ctx;
  const input = parseOrderBody(body, config);
  if (input.errors.length) throw validationError(input.errors);

  const customer = await verifyCustomer(ctx, token);
  logFields.customer = customer.numericId;

  const startMs = ctx.now();
  const since = new Date(startMs - 3600_000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const sinceMs = Date.parse(since);
  const tag = `idem-${idemKey}`;
  const idemQuery = `tag:"${tag}"`;
  const lineFirst = Math.max(1, Math.min(100, input.lines.length));

  // 1. One small read: the customer's lock, this key's drafts and orders, the last hour.
  let ownerId = adminIdCache.get(customer.id) ?? customer.id;
  let gate = await readGate(ctx, { ownerId, idemQuery, since });
  if (!gate?.customer) {
    // The Customer Account API id should be the Admin customer id; if Admin
    // has no such customer, look them up once by the verified email.
    const adminId = customer.email ? await adminCustomerByEmail(ctx, customer.email) : '';
    if (adminId && adminId !== ownerId) {
      rememberAdminId(customer.id, adminId);
      ownerId = adminId;
      gate = await readGate(ctx, { ownerId, idemQuery, since });
    }
    if (!gate?.customer) throw new ConfigError('The signed-in customer was not found through the Admin API (customer(id:) returned null).');
  }

  // 2. This key seen before (older keys, or another customer's)?
  const existing = findExisting(gate, tag, ownerId);
  if (existing.otherCustomer) {
    throw validationError([{ field: 'Idempotency-Key', message: 'This Idempotency-Key was already used. Send a new one for a new order.' }]);
  }
  if (existing.order) {
    logFields.outcome = 'replay';
    return replay(existing.order);
  }

  // 3. Take the customer's lock: wait for a running order, check the limit,
  //    quote, then compare-and-set.
  let snap = parseLock(gate.customer.lock);
  let polls = 0;
  let checkedDraft = '';
  /** An open draft an earlier attempt with this key left behind. */
  let ownDraft = null;
  let quote = null;
  const owner = randomUUID();
  let held = null;
  for (let round = 0; !held; round++) {
    if (round > WAIT_MAX_POLLS + 4) throw inProgress();
    const lock = snap.lock;
    const nowMs = ctx.now();

    if (lock?.key === idemKey && lock.orderId) {
      logFields.outcome = 'replay';
      return replayFromLock(lock);
    }
    if (isHeld(lock, nowMs)) {
      if (polls >= WAIT_MAX_POLLS || !(await pause(ctx, WAIT_POLL_MS))) throw inProgress();
      polls++;
      logFields.waited = polls;
      snap = await readLock(ctx, ownerId);
      continue;
    }

    // An earlier attempt with this key made a draft: finished, or still open?
    const candidate = (lock?.key === idemKey && lock.draftId) || existing.openDraftId || '';
    if (candidate && candidate !== checkedDraft) {
      checkedDraft = candidate;
      const state = await draftState(ctx, candidate, idemQuery, lineFirst);
      if (state?.status === 'COMPLETED' && state.order?.id) {
        const order = { ...state.order, customAttributes: state.order.customAttributes ?? state.customAttributes };
        await finishLock(ctx, ownerId, snap, lockAfterOrder({ ...(lock ?? {}), key: idemKey }, { owner, draftId: candidate, order, promise: attr(order.customAttributes, 'Delivery promise'), sinceMs, nowMs }), logFields);
        logFields.outcome = 'replay';
        return replay(order);
      }
      ownDraft = state?.status === 'OPEN' ? state : null;
    }

    // Per-customer limit (finishing this key's own draft is not a new order).
    if (!ownDraft) {
      const recent = countRecent(gate, lock, ownerId, sinceMs);
      if (recent.count >= config.maxOrdersPerHour) {
        const retry = recent.oldestMs ? Math.max(60, Math.ceil((recent.oldestMs + 3600_000 - nowMs) / 1000)) : 3600;
        logFields.outcome = 'limited';
        throw rateLimited(retry, `You can place at most ${config.maxOrdersPerHour} orders an hour. Please try again later.`);
      }
    }

    // Fresh quote from Shopify's prices and stock (once).
    if (!quote) {
      const variants = await fetchVariants(ctx, input.lines);
      quote = buildQuote({ lines: input.lines, delivery: input.delivery, variants, config, now: new Date(startMs) });
      const problems = [...quote.problems];
      if (input.expectedTotalFils !== undefined && input.expectedTotalFils !== quote.totalFils && !problems.length) {
        problems.push({
          variantId: null,
          kind: 'price_changed',
          message: `Your total changed from ${formatAed(input.expectedTotalFils)} to ${formatAed(quote.totalFils)}.`,
        });
      }
      if (problems.length) {
        if (ownDraft) await deleteDraft(ctx, ownDraft.id);
        logFields.outcome = 'quote_changed';
        return { status: 409, body: { error: 'quote_changed', message: problems[0].message, problems, quote } };
      }
      if (quote.subtotalFils < config.minOrderFils) {
        if (ownDraft) await deleteDraft(ctx, ownDraft.id);
        throw validationError([{ field: 'lines', message: `The minimum order is ${formatAed(config.minOrderFils)}. Add ${formatAed(config.minOrderFils - quote.subtotalFils)} more.` }]);
      }
    }

    const until = ctx.now() + LOCK_TTL_MS;
    const value = lockValue({
      key: idemKey,
      owner,
      until,
      draftId: ownDraft?.id ?? '',
      recent: pruneRecent(lock?.recent, sinceMs),
    });
    const res = await writeLock(ctx, ownerId, value, snap.digest);
    if (res.ok) {
      held = { value, digest: res.digest };
      ctx.mutationDeadline = until - LOCK_MARGIN_MS;
    } else {
      logFields.lockConflicts = (logFields.lockConflicts ?? 0) + 1;
      snap = await readLock(ctx, ownerId);
    }
  }

  // 4. Holding the lock: make (or finish) the draft and complete it.
  let finished = false;
  try {
    const termsId = config.paymentTermsTemplateId || termsCache.id || pickTermsTemplate(gate);
    termsCache.id = config.paymentTermsTemplateId ? '' : termsId;
    const promise = quote.deliveryPromise;
    if (input.delivery.promise && input.delivery.promise !== promise) logFields.promiseChanged = true;

    let draftId = '';
    if (ownDraft && sameLines(ownDraft, quote)) {
      draftId = ownDraft.id;
      logFields.resumed = true;
    } else if (ownDraft) {
      // Basket changed since that attempt: start again (the new draft id replaces it in the lock).
      await deleteDraft(ctx, ownDraft.id);
      held = { ...held, value: { ...held.value, draftId: '' } };
    }

    if (!draftId) {
      const draftInput = buildDraftInput({ customerId: ownerId, email: customer.email, input, quote, tag, promise, termsId });
      draftId = await createDraft(ctx, draftInput);
      // Remember the draft before anything else, so a retry finds this very
      // draft (set locally first: if this write fails, the release in
      // `finally` still records it).
      held = { ...held, value: { ...held.value, draftId } };
      held = await updateLock(ctx, ownerId, held, {}, logFields);
    }
    logFields.draft = numericId(draftId);

    // Wait until Shopify has finished calculating; clear leftovers of this key.
    const state = await waitReady(ctx, { draftId, tag, idemQuery, lineFirst, customerId: ownerId, logFields });
    if (state.other) {
      // An earlier attempt with this key had already completed an order.
      held = { ...held, value: { ...held.value, draftId: '' } };
      await finishLock(ctx, ownerId, held, lockAfterOrder(held.value, { owner, draftId: '', order: state.other, promise: attr(state.other.customAttributes, 'Delivery promise'), sinceMs, nowMs: ctx.now() }), logFields);
      finished = true;
      logFields.outcome = 'replay';
      return replay(state.other);
    }
    if (state.completed) {
      await finishLock(ctx, ownerId, held, lockAfterOrder(held.value, { owner, draftId, order: state.completed, promise, sinceMs, nowMs: ctx.now() }), logFields);
      finished = true;
      logFields.outcome = 'replay';
      return created(state.completed, promise, quote.totalFils, input.delivery.promise);
    }

    // Shopify's totals must equal the quote the customer accepted.
    const mismatch = compareDraft(state.draft, quote);
    if (mismatch) {
      await deleteDraft(ctx, draftId);
      held = { ...held, value: { ...held.value, draftId: '' } };
      if (state.draft.taxesIncluded === false) {
        throw new ConfigError('Shopify calculated tax on top of prices. Turn on "Include sales tax in product price and shipping rate" in Settings > Taxes and duties.');
      }
      logFields.outcome = 'total_mismatch';
      // No quote here: the app asks /api/quote again for the new numbers.
      return { status: 409, body: { error: 'quote_changed', message: mismatch[0].message, problems: mismatch } };
    }

    // Complete: the draft becomes a real order, payment due on fulfillment.
    const order = await completeDraft(ctx, draftId, logFields);
    logFields.order = order.name;
    logFields.financialStatus = order.displayFinancialStatus;
    logFields.outcome = 'created';
    await finishLock(ctx, ownerId, held, lockAfterOrder(held.value, { owner, draftId, order, promise, sinceMs, nowMs: ctx.now() }), logFields);
    finished = true;

    const totalFils = decimalToFils(order.totalPriceSet?.shopMoney?.amount) ?? quote.totalFils;
    if (order.displayFinancialStatus !== 'PENDING' && totalFils > 0) {
      // A COD order must stay payment pending; tell staff loudly if not.
      logFields.alert = 'cod_not_pending';
      await addTags(ctx, order.id, [CHECK_PAYMENT_TAG], logFields);
    }
    return created(order, promise, quote.totalFils, input.delivery.promise);
  } finally {
    // Any other way out: let the next attempt in now (keeping key and
    // draftId, so a retry with this key resumes the same draft).
    if (!finished) await releaseLock(ctx, ownerId, held, logFields);
  }
}

function created(order, promise, fallbackTotal, appPromise) {
  const body = {
    orderId: order.id,
    orderName: order.name,
    totalFils: decimalToFils(order.totalPriceSet?.shopMoney?.amount) ?? fallbackTotal,
    deliveryPromise: promise,
    paymentMethod: PAYMENT_METHOD,
  };
  // The app showed another promise (for example the 6 PM cut-off passed
  // while the shopper was paying): say so, so the app can point it out.
  if (appPromise && appPromise !== promise) body.promiseChanged = true;
  return { status: 201, body };
}

function inProgress() {
  return new UpstreamError('Another order for this customer is still being placed', { kind: 'in_progress', retryAfterSeconds: IN_PROGRESS_RETRY_S });
}

// ---- the customer's lock --------------------------------------------------

async function readGate(ctx, { ownerId, idemQuery, since }) {
  const { config } = ctx;
  const num = numericId(ownerId);
  return adminGraphql(
    ctx,
    GATE_QUERY,
    {
      customerId: ownerId,
      idem: idemQuery,
      recent: `customer_id:${num} created_at:>='${since}'`,
      recentDrafts: `customer_id:${num} status:open tag:app created_at:>='${since}'`,
      recentFirst: config.maxOrdersPerHour + 1,
      wantTerms: !config.paymentTermsTemplateId && !termsCache.id,
    },
    { label: 'gate' },
  );
}

async function readLock(ctx, ownerId) {
  const data = await adminGraphql(ctx, LOCK_QUERY, { customerId: ownerId }, { label: 'lock' });
  if (!data?.customer) throw new UpstreamError('The customer disappeared while ordering');
  return parseLock(data.customer.lock);
}

const GID = /^gid:\/\/shopify\/[A-Za-z]+\/\d+$/;
const str = (v, max = 200) => (typeof v === 'string' ? v.slice(0, max) : '');

/**
 * {digest, lock} from the metafield node. A value this server did not write
 * (or cannot read) counts as no lock, but its digest is kept so it can be
 * replaced safely.
 */
export function parseLock(node) {
  const digest = typeof node?.compareDigest === 'string' ? node.compareDigest : null;
  let raw = null;
  try {
    raw = typeof node?.value === 'string' ? JSON.parse(node.value) : null;
  } catch {
    raw = null;
  }
  if (!raw || typeof raw !== 'object' || raw.v !== 1) return { digest, lock: null };
  return { digest, lock: lockValue(raw) };
}

/** A clean lock value: only known fields, of the right types. */
export function lockValue(x) {
  return {
    v: 1,
    key: str(x.key, 36),
    owner: str(x.owner, 36),
    until: Number.isSafeInteger(x.until) ? x.until : 0,
    draftId: GID.test(x.draftId ?? '') ? x.draftId : '',
    orderId: GID.test(x.orderId ?? '') ? x.orderId : '',
    orderName: str(x.orderName, 40),
    totalFils: Number.isSafeInteger(x.totalFils) ? x.totalFils : 0,
    promise: str(x.promise, 120),
    recent: (Array.isArray(x.recent) ? x.recent : [])
      .filter((r) => r && GID.test(r.id ?? '') && Number.isSafeInteger(r.t))
      .map((r) => ({ id: r.id, t: r.t }))
      .slice(-120),
  };
}

/** Another request is placing an order right now (a lock dated too far ahead is broken, not held). */
function isHeld(lock, nowMs) {
  return Boolean(lock && !lock.orderId && lock.until > nowMs && lock.until <= nowMs + LOCK_TTL_MS + 60_000);
}

function pruneRecent(recent, sinceMs) {
  return (recent ?? []).filter((r) => r.t >= sinceMs);
}

function lockAfterOrder(base, { owner, draftId, order, promise, sinceMs, nowMs }) {
  const recent = pruneRecent(base.recent, sinceMs).filter((r) => r.id !== order.id);
  recent.push({ id: order.id, t: nowMs });
  return lockValue({
    key: base.key,
    owner,
    until: 0,
    draftId,
    orderId: order.id,
    orderName: order.name,
    totalFils: decimalToFils(order.totalPriceSet?.shopMoney?.amount) ?? 0,
    promise,
    recent,
  });
}

function isDigestConflict(e) {
  const path = Array.isArray(e?.field) ? e.field.join('.') : '';
  return e?.code === 'STALE_OBJECT' || e?.code === 'INVALID_COMPARE_DIGEST' || /compareDigest/.test(path);
}

/**
 * metafieldsSet with compare-and-set. {ok: false} when someone else changed
 * the lock first; other refusals are a setup error (scope, type).
 */
async function writeLock(ctx, ownerId, value, digest, { late = false } = {}) {
  const data = await adminGraphql(
    ctx,
    LOCK_SET_MUTATION,
    { metafields: [{ ownerId, namespace: LOCK_NAMESPACE, key: LOCK_KEY, type: 'json', value: JSON.stringify(value), compareDigest: digest }] },
    { mutation: true, label: 'lockSet', late },
  );
  const payload = data?.metafieldsSet;
  const errors = payload?.userErrors ?? [];
  if (errors.length) {
    if (errors.some(isDigestConflict)) return { ok: false };
    throw new ConfigError(`metafieldsSet refused the order lock: ${errors.map((e) => e?.code).filter(Boolean).join(',')} ${firstMessage(errors)}`.trim());
  }
  const next = payload?.metafields?.[0]?.compareDigest;
  return { ok: true, digest: typeof next === 'string' ? next : null };
}

/**
 * Changes the held lock. If the digest went stale, re-reads once and writes
 * again only if the lock is still this request's (same owner).
 */
async function updateLock(ctx, ownerId, held, patch, logFields, { late = false } = {}) {
  const value = lockValue({ ...held.value, ...patch });
  let digest = held.digest;
  for (let i = 0; i < 2; i++) {
    const res = digest === null ? { ok: false } : await writeLock(ctx, ownerId, value, digest, { late });
    if (res.ok) return { value, digest: res.digest };
    const now = await readLock(ctx, ownerId);
    if (now.lock?.owner !== held.value.owner) {
      logFields.lockLost = true;
      throw new UpstreamError('The order lock was taken over by another request');
    }
    digest = now.digest;
  }
  throw new UpstreamError('The order lock could not be updated');
}

/** Records the order in the lock and frees it. Best effort: the order exists either way. */
async function finishLock(ctx, ownerId, held, value, logFields) {
  try {
    if (held?.value?.owner === value.owner) {
      await updateLock(ctx, ownerId, held, value, logFields, { late: true });
    } else {
      // Not held (crash recovery): only if nobody changed the lock meanwhile.
      const res = await writeLock(ctx, ownerId, value, held?.digest ?? null, { late: true });
      if (!res.ok) logFields.lockWrite = 'skipped';
    }
  } catch (err) {
    logFields.lockWrite = err instanceof Error ? err.name : 'error';
  }
}

/** Frees the lock after a failed attempt, keeping key and draftId. Best effort. */
async function releaseLock(ctx, ownerId, held, logFields) {
  if (!held) return;
  try {
    await updateLock(ctx, ownerId, held, { until: 0 }, logFields, { late: true });
  } catch (err) {
    // It runs out by itself after LOCK_TTL_MS.
    logFields.lockRelease = err instanceof Error ? err.name : 'error';
  }
}

// ---- searches ---------------------------------------------------------------

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

/**
 * Orders in the last hour: the lock's own list (always up to date) joined
 * with what search finds (orders from elsewhere, open app drafts).
 */
export function countRecent(data, lock, customerId, sinceMs) {
  const seen = new Map();
  const add = (id, t) => {
    if (typeof id === 'string' && Number.isFinite(t) && t >= sinceMs) seen.set(id, Math.min(t, seen.get(id) ?? t));
  };
  for (const o of data?.recentOrders?.nodes ?? []) {
    if (o?.customer?.id === customerId) add(o.id, Date.parse(o.createdAt));
  }
  for (const r of lock?.recent ?? []) add(r.id, r.t);
  for (const d of data?.recentDrafts?.nodes ?? []) {
    if (d?.status === 'OPEN' && d?.customer?.id === customerId && Array.isArray(d.tags) && d.tags.includes('app')) add(d.id, Date.parse(d.createdAt));
  }
  const times = [...seen.values()];
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

function replayFromLock(lock) {
  return {
    status: 201,
    headers: { 'Idempotent-Replayed': 'true' },
    body: {
      orderId: lock.orderId,
      orderName: lock.orderName,
      totalFils: lock.totalFils,
      deliveryPromise: lock.promise,
      paymentMethod: PAYMENT_METHOD,
    },
  };
}

// ---- the draft ----------------------------------------------------------------

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

async function createDraft(ctx, draftInput) {
  const res = await adminGraphql(ctx, CREATE_MUTATION, { input: draftInput }, { mutation: true, label: 'draftOrderCreate' });
  const payload = res?.draftOrderCreate;
  if (payload?.userErrors?.length) {
    if (isCustomerError(payload.userErrors)) {
      throw new ConfigError(`draftOrderCreate rejected the customer: ${firstMessage(payload.userErrors)}`);
    }
    // Address and line errors are about what this customer typed: shown to them.
    throw validationError(payload.userErrors.map(mapUserError));
  }
  const id = payload?.draftOrder?.id;
  if (typeof id !== 'string') throw new UpstreamError('draftOrderCreate returned no draft');
  return id;
}

async function adminCustomerByEmail(ctx, email) {
  const found = await adminGraphql(ctx, CUSTOMER_BY_EMAIL_QUERY, { email }, { label: 'customerByIdentifier' });
  const id = found?.customerByIdentifier?.id;
  return typeof id === 'string' && /^gid:\/\/shopify\/Customer\/\d+$/.test(id) ? id : '';
}

function rememberAdminId(accountId, adminId) {
  if (adminIdCache.size >= 1000) adminIdCache.delete(adminIdCache.keys().next().value);
  adminIdCache.set(accountId, adminId);
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
 * Polls `ready`. The lock means no other request is working on this key, so
 * other drafts with this key are leftovers of earlier attempts: an open one
 * is deleted; a completed one means the order already exists, and this
 * draft is deleted instead.
 */
async function waitReady(ctx, { draftId, tag, idemQuery, lineFirst, customerId, logFields }) {
  const cleared = new Set();
  for (let attempt = 0; attempt < 8; attempt++) {
    const state = await draftState(ctx, draftId, idemQuery, lineFirst);
    if (!state) throw new UpstreamError('Draft order disappeared before completion');
    const others = state.siblings.filter((d) => d?.id !== draftId && Array.isArray(d?.tags) && d.tags.includes(tag) && d.customer?.id === customerId);
    const done = others.find((d) => d.status === 'COMPLETED');
    if (done) {
      logFields.duplicate = true;
      await deleteDraft(ctx, draftId);
      const order = await completedOrder(ctx, done.id);
      if (order) return { other: order };
      throw new UpstreamError('An earlier draft for this order could not be read');
    }
    for (const d of others) {
      if (d.status === 'OPEN' && !cleared.has(d.id)) {
        cleared.add(d.id);
        logFields.leftovers = cleared.size;
        await deleteDraft(ctx, d.id);
      }
    }
    if (state.status === 'COMPLETED' && state.order?.id) return { completed: state.order };
    if (state.ready) return { draft: state };
    if (!(await pause(ctx, 400 + attempt * 200))) break;
  }
  throw new UpstreamError('The draft order did not become ready in time');
}

async function completedOrder(ctx, id) {
  const data = await adminGraphql(ctx, WINNER_QUERY, { id }, { label: 'draftWinner' });
  const d = data?.draftOrder;
  if (d?.status === 'COMPLETED' && d.order?.id) {
    return { ...d.order, customAttributes: d.order.customAttributes ?? d.customAttributes };
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

async function completeDraft(ctx, id, logFields) {
  const data = await adminGraphql(ctx, COMPLETE_MUTATION, { id }, { mutation: true, label: 'draftOrderComplete' });
  const payload = data?.draftOrderComplete;
  const order = payload?.draftOrder?.order;
  if (order?.id) return order;
  if (payload?.userErrors?.length) {
    // Already completed (an earlier attempt's request may have gone through)?
    const check = await adminGraphql(ctx, WINNER_QUERY, { id }, { label: 'draftWinner' });
    if (check?.draftOrder?.status === 'COMPLETED' && check.draftOrder.order?.id) return check.draftOrder.order;
    await deleteDraft(ctx, id);
    logFields.completeError = true;
    // Shopify's own text goes to the log only (scrubbed there).
    throw new ApiError(
      422,
      'invalid',
      'We could not place the order. Please check your basket and try again.',
      { field: 'order', errors: [{ field: 'order', message: 'We could not place the order. Please check your basket and try again.' }] },
      {},
      `draftOrderComplete: ${firstMessage(payload.userErrors)}`,
    );
  }
  throw new UpstreamError('draftOrderComplete returned no order');
}

async function deleteDraft(ctx, id) {
  try {
    await adminGraphql(ctx, DELETE_MUTATION, { input: { id } }, { mutation: true, label: 'draftOrderDelete', late: true });
  } catch (err) {
    // Best effort: an orphan draft is harmless (never charged, auto-deleted after a year of inactivity).
    ctx.log?.({ event: 'draft_delete_failed', draft: numericId(id), reason: err instanceof Error ? err.name : 'error' });
  }
}

async function addTags(ctx, id, tags, logFields) {
  try {
    const data = await adminGraphql(ctx, TAGS_ADD_MUTATION, { id, tags }, { mutation: true, label: 'tagsAdd', late: true });
    if (data?.tagsAdd?.userErrors?.length) logFields.tagsAdd = 'refused';
  } catch (err) {
    logFields.tagsAdd = err instanceof Error ? err.name : 'error';
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
