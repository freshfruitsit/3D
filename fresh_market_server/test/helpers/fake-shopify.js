// A small in-memory Shopify that answers the exact requests this server
// makes: the client credentials token endpoint, Customer Account API
// discovery and `customer` query, and the Admin GraphQL operations by name.
// No network is used.

export const STORE = 'testtfm.myshopify.com';
export const CUSTOMER_API = 'https://shopify.com/79173124173/account/customer/api/2026-10/graphql';
export const ADMIN_API = `https://${STORE}/admin/api/2026-10/graphql.json`;

export const ENV = Object.freeze({
  SHOPIFY_STORE_DOMAIN: STORE,
  SHOPIFY_SHOP_ID: '79173124173',
  SHOPIFY_API_VERSION: '2026-10',
  SHOPIFY_CLIENT_ID: 'test-client-id',
  SHOPIFY_CLIENT_SECRET: 'test-client-secret',
  DELIVERY_FEE_AED: '25',
  FREE_DELIVERY_FROM_AED: '200',
  MIN_ORDER_AED: '0',
});

/** 10:07 UAE time on 14 Nov 2026 (06:07 UTC): same day, Express open. */
export const NOON_ISH = Date.UTC(2026, 10, 14, 6, 7);

/** A UTC instant for a UAE wall-clock time on 14 Nov 2026. */
export function uae(hour, minute = 0) {
  return Date.UTC(2026, 10, 14, hour - 4, minute);
}

export function variant(id, { price, title = 'Default Title', product = `Product ${id}`, tags = [], available = true, tracked = false, policy = 'DENY', qty = 100, status = 'ACTIVE' } = {}) {
  return {
    id: `gid://shopify/ProductVariant/${id}`,
    title,
    price,
    availableForSale: available,
    inventoryPolicy: policy,
    inventoryQuantity: qty,
    inventoryItem: { tracked },
    product: { title: product, status, tags },
  };
}

export const CATALOG = () => [
  variant(2001, { price: '19.95', title: '500 GM', product: 'Fresh Strawberries', tags: ['1hr-delivery'], tracked: true, qty: 10 }),
  variant(2004, { price: '2.50', title: '500 GM', product: 'Tomatoes', tags: ['Vegetables'] }),
  variant(2007, { price: '300.00', product: 'Saffron', tags: ['1HR-Delivery '] }),
  variant(2008, { price: '20.50', title: '250 GM', product: 'Blueberries', available: false, tracked: true, qty: 0 }),
  variant(2009, { price: '75.00', title: '1 KG', product: 'Lamb', tracked: true, qty: 2 }),
];

export const CUSTOMER = Object.freeze({
  token: 'shcat_good_token',
  id: 'gid://shopify/Customer/7001',
  email: 'sara@example.com',
});

const json = (status, body, headers = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } });

/**
 * @param {{now?: () => number}} [opts]
 */
export function fakeShopify({ now = () => NOON_ISH } = {}) {
  const s = {
    variants: new Map(CATALOG().map((v) => [v.id, v])),
    customers: new Map([[CUSTOMER.token, { id: CUSTOMER.id, firstName: 'Sara', lastName: 'Ahmed', emailAddress: { emailAddress: CUSTOMER.email }, phoneNumber: { phoneNumber: '+971501234567' } }]]),
    drafts: [],
    orders: [],
    nextDraft: 900001,
    nextOrder: 800001,
    nextNumber: 1001,
    taxesIncluded: true,
    readyAfterPolls: 0,
    /** gid -> price string Shopify uses on the draft (simulates a change after the quote) */
    draftPrice: new Map(),
    termsTemplates: [
      { id: 'gid://shopify/PaymentTermsTemplate/1', name: 'Due on receipt', paymentTermsType: 'RECEIPT' },
      { id: 'gid://shopify/PaymentTermsTemplate/7', name: 'Due on fulfillment', paymentTermsType: 'FULFILLMENT' },
    ],
    /** opName -> queue of functions returning a Response to send instead */
    overrides: new Map(),
    calls: [],
    tokenRequests: 0,
    discoveryRequests: 0,
    customerRequests: 0,
    adminTokens: [],
  };

  s.override = (op, fn) => {
    if (!s.overrides.has(op)) s.overrides.set(op, []);
    s.overrides.get(op).push(fn);
  };
  s.ops = (name) => s.calls.filter((c) => c.op === name);

  const cost = { requestedQueryCost: 50, actualQueryCost: 20, throttleStatus: { maximumAvailable: 2000, currentlyAvailable: 1950, restoreRate: 100 } };

  function tagOf(query) {
    const m = /tag:"([^"]+)"/.exec(query ?? '');
    return m ? m[1] : null;
  }

  function search(list, query) {
    const tag = tagOf(query);
    const cust = /customer_id:(\d+)/.exec(query ?? '');
    const since = /created_at:>='([^']+)'/.exec(query ?? '');
    const status = /status:(\w+)/.exec(query ?? '');
    const plainTag = /(?:^|\s)tag:(\w+)/.exec(query ?? '');
    return list.filter((x) => {
      if (tag && !x.tags.includes(tag)) return false;
      if (plainTag && !x.tags.includes(plainTag[1])) return false;
      if (cust && x.customer?.id !== `gid://shopify/Customer/${cust[1]}`) return false;
      if (since && Date.parse(x.createdAt) < Date.parse(since[1])) return false;
      if (status && x.status.toLowerCase() !== status[1].toLowerCase()) return false;
      return true;
    });
  }

  const money = (fils) => ({ shopMoney: { amount: (fils / 100).toFixed(2), currencyCode: 'AED' } });
  const toFils = (str) => Math.round(Number(str) * 100);

  function draftView(d) {
    const ready = d.polls >= s.readyAfterPolls;
    return {
      id: d.id,
      name: d.name,
      status: d.status,
      ready,
      tags: d.tags,
      taxesIncluded: s.taxesIncluded,
      customer: d.customer,
      customAttributes: d.input.customAttributes,
      totalPriceSet: money(d.totalFils),
      lineItems: { nodes: d.lines.map((l) => ({ variant: { id: l.variantId }, quantity: l.quantity, originalUnitPriceSet: money(l.unitFils) })) },
      order: d.orderId ? orderView(s.orders.find((o) => o.id === d.orderId)) : null,
      createdAt: d.createdAt,
    };
  }

  function orderView(o) {
    return o && { id: o.id, name: o.name, tags: o.tags, customer: o.customer, displayFinancialStatus: o.displayFinancialStatus, totalPriceSet: money(o.totalFils), customAttributes: o.customAttributes, createdAt: o.createdAt };
  }

  function admin(op, variables) {
    switch (op) {
      case 'FreshMarketVariants':
        return { shop: { currencyCode: 'AED' }, nodes: variables.ids.map((id) => s.variants.get(id) ?? null) };
      case 'FreshMarketPrepare':
        return {
          shop: { currencyCode: 'AED' },
          nodes: variables.ids.map((id) => s.variants.get(id) ?? null),
          idemDrafts: { nodes: search(s.drafts, variables.idem).slice(0, 5).map(draftView) },
          idemOrders: { nodes: search(s.orders, variables.idem).slice(0, 3).map(orderView) },
          recentOrders: { nodes: search(s.orders, variables.recent).reverse().slice(0, variables.recentFirst).map(orderView) },
          recentDrafts: { nodes: search(s.drafts, variables.recentDrafts).reverse().slice(0, variables.recentFirst).map(draftView) },
          ...(variables.wantTerms ? { paymentTermsTemplates: s.termsTemplates } : {}),
        };
      case 'FreshMarketDraftCreate': {
        const input = variables.input;
        const customerId = input.purchasingEntity?.customerId;
        if (!/^gid:\/\/shopify\/Customer\/\d+$/.test(customerId ?? '')) {
          return { draftOrderCreate: { draftOrder: null, userErrors: [{ field: ['input', 'purchasingEntity', 'customerId'], message: 'Customer does not exist' }] } };
        }
        if (s.createUserErrors) {
          return { draftOrderCreate: { draftOrder: null, userErrors: s.createUserErrors } };
        }
        const lines = input.lineItems.map((li) => {
          const v = s.variants.get(li.variantId);
          const price = s.draftPrice.get(li.variantId) ?? v.price;
          return { variantId: li.variantId, quantity: li.quantity, unitFils: toFils(price) };
        });
        const subtotal = lines.reduce((a, l) => a + l.unitFils * l.quantity, 0);
        const ship = toFils(input.shippingLine.priceWithCurrency.amount);
        const gross = subtotal + ship;
        const totalFils = s.taxesIncluded ? gross : Math.round(gross * 1.05);
        const d = {
          id: `gid://shopify/DraftOrder/${s.nextDraft++}`,
          name: `#D${s.drafts.length + 1}`,
          status: 'OPEN',
          tags: [...input.tags],
          customer: { id: customerId },
          input,
          lines,
          totalFils,
          polls: 0,
          createdAt: new Date(now()).toISOString(),
        };
        s.drafts.push(d);
        return { draftOrderCreate: { draftOrder: { id: d.id, name: d.name, ready: s.readyAfterPolls === 0, status: d.status }, userErrors: [] } };
      }
      case 'FreshMarketDraftState': {
        const d = s.drafts.find((x) => x.id === variables.id);
        if (d) d.polls++;
        return { draftOrder: d ? draftView(d) : null, draftOrders: { nodes: search(s.drafts, variables.idem).slice(0, 5).map(draftView) } };
      }
      case 'FreshMarketDraftWinner': {
        const d = s.drafts.find((x) => x.id === variables.id);
        return { draftOrder: d ? draftView(d) : null };
      }
      case 'FreshMarketDraftComplete': {
        const d = s.drafts.find((x) => x.id === variables.id);
        if (!d) return { draftOrderComplete: { draftOrder: null, userErrors: [{ field: ['id'], message: 'Draft order not found' }] } };
        if (s.completeUserErrors) return { draftOrderComplete: { draftOrder: null, userErrors: s.completeUserErrors } };
        const o = {
          id: `gid://shopify/Order/${s.nextOrder++}`,
          name: `#${s.nextNumber++}`,
          tags: [...d.tags],
          customer: d.customer,
          customAttributes: d.input.customAttributes,
          totalFils: d.totalFils,
          displayFinancialStatus: d.input.paymentTerms ? 'PENDING' : 'PAID',
          createdAt: new Date(now()).toISOString(),
        };
        s.orders.push(o);
        d.status = 'COMPLETED';
        d.orderId = o.id;
        return { draftOrderComplete: { draftOrder: { id: d.id, status: d.status, order: orderView(o) }, userErrors: [] } };
      }
      case 'FreshMarketDraftDelete': {
        const i = s.drafts.findIndex((x) => x.id === variables.input.id);
        if (i >= 0) s.drafts.splice(i, 1);
        return { draftOrderDelete: { deletedId: variables.input.id, userErrors: [] } };
      }
      case 'FreshMarketCustomerByEmail':
        return { customerByIdentifier: s.adminCustomerByEmail ? { id: s.adminCustomerByEmail } : null };
      default:
        throw new Error(`fake Shopify: unknown operation ${op}`);
    }
  }

  async function fetch(input, init = {}) {
    const url = String(input);
    const headers = new Headers(init.headers ?? {});
    if (url === `https://${STORE}/admin/oauth/access_token`) {
      s.tokenRequests++;
      const form = new URLSearchParams(String(init.body));
      if (form.get('grant_type') !== 'client_credentials' || form.has('scope')) return json(400, { error: 'invalid_request' });
      if (form.get('client_id') !== ENV.SHOPIFY_CLIENT_ID || form.get('client_secret') !== ENV.SHOPIFY_CLIENT_SECRET) {
        return json(401, { error: 'invalid_client' });
      }
      const token = `admin-token-${s.tokenRequests}`;
      s.adminTokens.push(token);
      return json(200, { access_token: token, scope: 'read_products,write_draft_orders', expires_in: 86399 });
    }
    if (url === `https://${STORE}/.well-known/customer-account-api`) {
      s.discoveryRequests++;
      return json(200, { graphql_api: CUSTOMER_API, mcp_api: 'https://shopify.com/79173124173/account/customer/api/mcp' });
    }
    if (url === CUSTOMER_API) {
      s.customerRequests++;
      const auth = headers.get('authorization');
      const ov = s.overrides.get('customer')?.shift();
      if (ov) return ov();
      const c = s.customers.get(auth ?? '');
      if (!c) return json(401, { errors: 'User does not have access' });
      return json(200, { data: { customer: c } });
    }
    if (url === ADMIN_API) {
      const token = headers.get('x-shopify-access-token');
      const body = JSON.parse(String(init.body));
      const op = /^(?:query|mutation)\s+(\w+)/.exec(body.query.trim())?.[1] ?? 'anonymous';
      s.calls.push({ op, variables: body.variables, token });
      if (!s.adminTokens.includes(token) && token !== s.legacyToken) {
        return json(401, { errors: '[API] Invalid API key or access token (unrecognized login or wrong password)' });
      }
      const ov = s.overrides.get(op)?.shift();
      if (ov) return ov();
      return json(200, { data: admin(op, body.variables), extensions: { cost } });
    }
    throw new Error(`fake Shopify: unexpected request to ${url}`);
  }

  s.fetch = fetch;
  return s;
}

export const responses = {
  throttled: () =>
    json(200, {
      errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED', documentation: 'https://shopify.dev/api/usage/rate-limits' } }],
      extensions: { cost: { requestedQueryCost: 120, actualQueryCost: null, throttleStatus: { maximumAvailable: 2000, currentlyAvailable: 20, restoreRate: 100 } } },
    }),
  serverError: () => json(502, { errors: 'Bad gateway' }),
  networkError: () => {
    throw new TypeError('fetch failed');
  },
  customerThrottled: () => json(429, { errors: [{ message: 'Throttled', extensions: { code: 'THROTTLED' } }] }, { 'Retry-After': '30' }),
  unauthorized: () => json(401, { errors: 'User does not have access' }),
};
