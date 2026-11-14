# Fresh Market order server

A small server for the Fresh Market Android app's own checkout. The app sends
the basket here. The server reads the real prices and stock from Shopify,
checks the delivery rules, and creates the order in Shopify as **Cash on
Delivery**. In Shopify the order shows as payment pending, and staff mark it
paid when the driver collects the cash.

- Runs as Vercel Functions on Node.js 22 (`api/`). No framework and no npm
  dependencies. Tests use the built-in `node:test`.
- Shopify Admin GraphQL API version **2026-10**, the latest stable version
  ([versioning](https://shopify.dev/docs/api/usage/versioning)).
- Money is always whole **fils** (1 AED = 100 fils). Prices include VAT, so
  `total = subtotal + delivery fee`.

```
npm install   # nothing to download; it creates the lockfile
npm test      # 75 tests, Shopify replaced by an in-memory fake
```

## API

Every response is JSON with `Cache-Control: no-store` and an `X-Request-Id`
header. Errors look like this:
`{error, message, field?, errors?, retryable?, retryAfterSeconds?, requestId}`.

### `GET /api/health`

`200 {ok: true, version: "1.0.0"}`

### `POST /api/quote`

No sign-in needed.

```jsonc
// request
{
  "lines": [{ "variantId": 44123 /* or "44123" or "gid://shopify/ProductVariant/44123" */, "quantity": 2 }],
  "delivery": { "mode": "express" /* or "market" */,
                "area": { "name": "Mirdif", "emirate": "dubai", "lat": 25.22, "lng": 55.42 } }
}
// 200
{
  "lines": [{ "variantId": 44123, "title": "Fresh Strawberries", "variantTitle": "500 GM",
              "quantity": 2, "unitPriceFils": 1995, "lineTotalFils": 3990, "available": true }],
  "subtotalFils": 3990, "deliveryFeeFils": 2500, "totalFils": 6490, "currency": "AED",
  "deliveryPromise": "25–35 min",
  "problems": [{ "variantId": 44123, "kind": "sold_out|price_changed|not_express|qty_reduced", "message": "..." }],
  "minOrderFils": 0
}
```

Emirate codes: `dubai auh shj ajm uaq rak fuj`.

### `POST /api/orders`

Headers: `Authorization: Bearer <Customer Account API access token>`,
`Idempotency-Key: <a new UUID per order; the same UUID on every retry of that order>`.

```jsonc
{
  "lines": [{ "variantId": 44123, "quantity": 2 }],
  "delivery": { "mode": "market", "area": { "name": "Mirdif", "emirate": "dubai", "lat": 25.22, "lng": 55.42 },
                "promise": "Today within 6 hours", "pin": "25.22000,55.42000" },
  "address": { "firstName": "Sara", "lastName": "Ahmed", "address1": "Bay Square, Building 5",
               "address2": "Flat 302", "city": "Mirdif", "emirate": "dubai", "phone": "050 123 4567" },
  "instructions": "Call when you arrive",
  "note": "optional order note"
}
```

| Status | Body | When |
|---|---|---|
| 201 | `{orderId: "gid://shopify/Order/…", orderName: "#1001", totalFils, deliveryPromise, paymentMethod: "Cash on Delivery"}` | Order created. A retry with the same key gets the same body again, with the header `Idempotent-Replayed: true`. |
| 401 | `{error: "unauthorized"}` | The token is missing, invalid or expired. Sign the customer in again. |
| 409 | `{error: "quote_changed", problems, quote?}` | Something is sold out, has less stock, costs a different price, or can't go by Express. Show the problems, then quote again. |
| 422 | `{error: "invalid", field, message, errors}` | A field is wrong, the basket is below the minimum order, or the key was already used by another customer. |
| 429 | `{error: "rate_limited", retryAfterSeconds}` + `Retry-After` | The customer placed too many orders this hour, or Shopify is limiting this customer. |
| 5xx | `{retryable: true or false}` | Shopify is busy or down (`503`, retry with the **same** key), or the server is set up wrongly (`500`, `retryable: false`). |

Other answers: `400` for a body that isn't JSON, `413` for a body over
64 KB, `415` when the body isn't sent as JSON, `405` for the wrong method.

**Small additions to the contract.** Nothing in the agreed contract changed.

- `problems[].variantId` is `null` when the problem is about the whole
  basket. Two cases: Express isn't available in this area, or Shopify's total
  differs from the quote.
- A line may carry an optional `unitPriceFils`: the price the app showed.
  When it differs from Shopify's price, the server reports `price_changed`.
  The app's price is never used for charging.
- The order body may carry an optional `expectedTotalFils`. When it differs
  from the new total, the server reports `price_changed`.
- A 409 that comes before any draft is made includes the fresh `quote`.

### Rules the server applies

These come from the app's `lib/delivery/` and are copied into
`lib/delivery.js`. Keep both in step.

- **Fresh Market**
  - Before the 6 PM cut-off (Dubai time, UTC+4), the promise is
    "Today within 6 hours".
  - From 6 PM it is "Tomorrow morning before 11 AM".
- **Express**
  - Only for products tagged `1hr-delivery` (any letter case).
  - Only within 20 km of the Ras Al Khor hub.
  - While open (8 AM to 10 PM), the promise is the ETA, for example
    "25–35 min".
  - While closed, the app still lets the shopper choose Express. The server
    then promises "Today from 8 AM" or "Tomorrow from 8 AM" instead of
    minutes.
- **Promise text:** the server works it out itself. The `promise` the app
  sends is ignored.
- **Where we deliver:** the pin must be within 60 km of one of the app's
  areas. The address emirate must match the delivery area's emirate.
- **Delivery fee:** `DELIVERY_FEE_AED`.
  - Free when the subtotal is at least `FREE_DELIVERY_FROM_AED`. If you set
    it to 0, delivery is always free.
  - No fee when nothing in the basket is available.
- **Limits:**
  - Each line: quantity 1 to `MAX_QTY_PER_LINE`.
  - At most `MAX_LINES` different items.
  - At most `MAX_ORDERS_PER_HOUR` orders per customer. This counts orders
    from the last hour plus open app drafts.
- **Mobile numbers:** read the same way as in the app, then stored as
  `+9715XXXXXXXX`.

## How an order is made

For `POST /api/orders`, the server does this:

1. **Check the customer.** It sends the token to the Customer Account API,
   at the endpoint the shop publishes at
   `https://testtfm.myshopify.com/.well-known/customer-account-api`, and asks
   `customer { id emailAddress { emailAddress } phoneNumber { phoneNumber } }`.
   A good answer is remembered for 60 seconds (only a SHA-256 hash of the
   token is kept). A 401 from Shopify becomes our 401.
2. **Read Shopify in one Admin query.** One query fetches:
   - the shop currency (it must be AED),
   - each variant's price, stock, status and tags,
   - any draft or order already tagged `idem-<key>`,
   - this customer's orders from the last hour,
   - the "Due on fulfillment" payment terms template.
3. **Seen this key before?**
   - The order already exists: return it.
   - An open draft from a failed attempt exists: finish it if it still
     matches the basket, otherwise delete it.
   - Another customer used the key: 422.
4. **Apply the per-customer limit.** Over the limit: 429.
5. **Work out the quote.** If anything changed: 409. Below the minimum
   order: 422.
6. **Create the draft** with `draftOrderCreate`. The draft gets:
   - the customer, and their verified email so Shopify sends the order
     confirmation,
   - AED as the currency, with automatic discounts off so Shopify's total
     equals the quote,
   - the variant lines,
   - a custom shipping line ("Fresh Market delivery" or "Express delivery")
     with the fee,
   - the shipping address, also used as the billing address: country AE,
     the province code for the emirate (dubai DU, auh AZ, shj SH, ajm AJ,
     uaq UQ, rak RK, fuj FU), and the phone,
   - the note,
   - tags `app`, `cod`, `idem-<key>`,
   - custom attributes: Delivery mode, Delivery area, Delivery promise,
     Delivery pin, Delivery instructions, Source = Fresh Market app,
     Payment method = Cash on Delivery,
   - `paymentTerms` with the due-on-fulfillment template.
7. **Wait until the draft is `ready`.** If two requests with the same key
   made two drafts, the later one deletes itself and returns the earlier
   one's order.
8. **Compare Shopify's draft with the quote.** If the prices or total
   differ, delete the draft and return 409. If Shopify added tax on top of
   the prices, delete the draft and return 500 (a store setting; see setup
   step 5).
9. **Complete the draft** with `draftOrderComplete`. The order is created
   with payment due on fulfillment, and inventory is committed.

The deprecated `paymentPending` flag is not used. Shopify's deprecation note
says: "Create a draft with payment terms rather than marking the draft as
pending."

**Retries and errors**

- If Shopify answers THROTTLED, the server waits the time Shopify's cost data
  asks for (at least 1 second) and tries again, up to 3 tries.
- Reads are also retried on network errors and 5xx.
- Mutations are never resent after a network error or 5xx, because they
  might have gone through. The app retries with the same Idempotency-Key and
  step 3 picks up where it stopped.
- The Admin token (client credentials grant) is kept in memory and renewed
  60 seconds before it expires. After a 401 or ACCESS_DENIED it is renewed
  once and the call is tried again.
- Logs hold ids, counts, codes and timings only. They never hold tokens,
  secrets, names, emails, phones or addresses.

## Owner setup, step by step

These are done once in Shopify and Vercel. Do them on the dev store
(testtfm) first, then again on the production store.

1. **Turn on the new customer accounts.** Shopify admin > Settings >
   Customer accounts > Edit > choose "Customer accounts" > Save.
2. **Add the free Headless sales channel** from the Shopify App Store. Open
   it and click **Create storefront**.
3. **Set up sign-in for the app.** Open Headless > your storefront >
   Customer Account API settings:
   - Client type: **Public**, **Mobile**. Copy the **Client ID** into the
     app.
   - Callback URL: `shop.79173124173.app://callback`.
   - JavaScript origins: leave empty.
   - Permissions: allow the customer's name, email and phone, and orders.
4. **Turn on Cash on Delivery.** Settings > Payments > Manual payment
   methods > **Cash on Delivery (COD)**. Staff use it when they mark an order
   paid.
5. **Check taxes.** Settings > Taxes and duties: UAE VAT is collected and
   **"Include sales tax in product price and shipping rate"** is on. The
   server refuses orders if Shopify adds tax on top of the prices.
6. **Create the server's Shopify app.**
   1. Settings > Apps > Develop apps > **Build apps in Dev Dashboard** >
      Create app > Start from Dev Dashboard. Name it, for example,
      "Fresh Market server".
   2. Create a version:
      - App URL: the default `https://shopify.dev/apps/default-app-home`.
      - Webhooks API version: `2026-10`.
      - Scopes: `read_products`, `read_inventory`, `read_draft_orders`,
        `write_draft_orders`, `read_orders`, `write_orders`,
        `read_customers`, `read_payment_terms`, `write_payment_terms`.
      - Release the version.
   3. Installs > Install app > pick the store > Install.
   4. App > Settings: copy the **Client ID** and the **Client secret**.
   5. You need the **App developer** role to do this.
   6. If the server's logs later show `shop_not_permitted`, the store is not
      in the same Shopify organization as the app. Create the app from that
      store's own admin. The dev store and the production store may need one
      app each.
7. **Add the settings in Vercel.** Project > Settings > Environment
   Variables (see the table below). Mark `SHOPIFY_CLIENT_SECRET` as
   **Sensitive**. Paste it yourself; never send it in chat or commit it. If
   the dev store and the production store need different apps, give Preview
   and Production their own values.
8. **Optional:** Settings > Notifications > Order confirmation. Add a line
   such as "Pay cash on delivery".
9. **Leave the Dev Dashboard IP allowlist off.** Vercel's outgoing IP
   addresses change.

## Environment variables

| Name | Example / default | Secret | Notes |
|---|---|---|---|
| `SHOPIFY_STORE_DOMAIN` | `testtfm.myshopify.com` | no | Required. |
| `SHOPIFY_SHOP_ID` | `79173124173` | no | Used if the Customer Account API discovery fails. |
| `SHOPIFY_API_VERSION` | `2026-10` | no | Default `2026-10`. |
| `SHOPIFY_CLIENT_ID` | from Dev Dashboard | no | Client credentials grant. |
| `SHOPIFY_CLIENT_SECRET` | from Dev Dashboard | **yes** | Only in Vercel, marked Sensitive. |
| `SHOPIFY_ADMIN_TOKEN` | — | **yes** | Optional. Only for a legacy admin-created custom app made before 2026-01-01; it replaces the client ID and secret. |
| `DELIVERY_FEE_AED` | `25` | no | |
| `FREE_DELIVERY_FROM_AED` | `200` | no | 0 means delivery is always free. |
| `MIN_ORDER_AED` | `0` | no | |
| `MAX_LINES` | `50` | no | 1 to 100. |
| `MAX_QTY_PER_LINE` | `50` | no | |
| `MAX_ORDERS_PER_HOUR` | `5` | no | Per customer. |
| `CUSTOMER_ACCOUNT_API_URL` | discovered | no | Optional override. |
| `SHOPIFY_PAYMENT_TERMS_TEMPLATE_ID` | looked up | no | Optional, for example `gid://shopify/PaymentTermsTemplate/7`. |

`.env.example` lists the same names, with no values for the secrets.

## Deploy (Vercel team "Horeca")

1. Create a project from this repository with **Root Directory**
   `fresh_market_server` and Framework Preset **Other**. Leave Build Command
   and Install Command empty. `vercel.json` already sets
   `framework: null`, `outputDirectory: public`, the region and
   `maxDuration`. `.vercelignore` uploads only `api/`, `lib/`, `public/`
   and the package and Vercel files.
2. Add the environment variables above (step 7 of the owner setup).
3. Deploy. Check `GET https://<project>.vercel.app/api/health`, which
   should return `{"ok":true,"version":"1.0.0"}`.
4. On the dev store, place one test order from the app. Then check the
   points in "Check on the dev store" below.
5. Optional: add a Vercel Firewall rate-limit rule for `/api/quote`. It needs
   no sign-in, and every call reads the Admin API.

**Region: `bom1` (Mumbai).**

- From the regions I know, Mumbai is the closest Vercel compute region to
  the UAE. That keeps the phone-to-server leg short.
- Shopify does not say where its Admin API servers are. An order makes 5 to
  7 Shopify calls one after another, so if the logs show slow Shopify calls,
  try `fra1` or `iad1`.
- Each log line includes `ms` and `shopifyCalls`, so the two regions can be
  compared.
- If Vercel has added a UAE region by now, use that.

`maxDuration` is 30 seconds. The server stops waiting on Shopify after
25 seconds and answers 503 `retryable`.

## Check on the dev store

There was no Admin token while this was built, so these points could not be
tried:

1. That a "Due on fulfillment" template exists in
   `paymentTermsTemplates(paymentTermsType: FULFILLMENT)`. If it does,
   optionally pin its id in `SHOPIFY_PAYMENT_TERMS_TEMPLATE_ID`.
2. That a draft completed with those payment terms shows **Payment
   pending**, and that the customer gets the order confirmation email. The
   log line shows `financialStatus`, which should be `PENDING`.
3. That the draft's tags, custom attributes and note carry over to the
   order. The idempotency lookup also checks the order itself, so it still
   works if tags don't carry over.
4. That the Customer Account API `customer.id` is accepted as
   `purchasingEntity.customerId`. If it isn't, the server looks the customer
   up by their verified email, and the logs show a second
   `draftOrderCreate`.
5. How quickly the tag search finds a new draft or order. Retries rely on
   it. The app should also stop double taps.
6. That Shopify accepts a shipping phone or email that differs from the
   customer profile.
7. That a token from the Mobile public client works when the server sends
   it with no `Origin` header. Shopify's 401 `invalid_token` note about
   `Origin` is written for web clients.
8. That the new customer accounts are switched on for testtfm.

## Files

- `api/health.js`, `api/quote.js`, `api/orders.js`: Vercel entry points
  (`export default { fetch }`).
- `lib/handlers.js`: the routes, which take a fetch and a clock so tests can
  pass their own.
- `lib/orders.js`: the order flow (draft, ready, compare, complete;
  idempotency; limits).
- `lib/quote.js`: variant read and quote maths.
- `lib/delivery.js`: the app's delivery rules, emirates and province codes.
- `lib/shopify-admin.js`: the Admin GraphQL client (token, throttling,
  retries).
- `lib/shopify-customer.js`: the Customer Account API token check.
- `lib/validate.js`, `lib/money.js`, `lib/config.js`, `lib/errors.js`,
  `lib/http.js`.
- `test/`: unit and flow tests with an in-memory fake Shopify
  (`test/helpers/fake-shopify.js`).

## Sources

All copies are saved with the research notes.

- Client credentials grant:
  https://shopify.dev/docs/apps/build/authentication-authorization/client-credentials-grant
- No new legacy custom apps from 2026-01-01:
  https://help.shopify.com/en/manual/apps/managing-apps
- Draft orders:
  - https://shopify.dev/docs/api/admin-graphql/2026-10/mutations/draftOrderCreate
  - https://shopify.dev/docs/api/admin-graphql/2026-10/mutations/draftOrderComplete
  - https://shopify.dev/docs/api/admin-graphql/2026-10/input-objects/DraftOrderInput
  - https://shopify.dev/docs/api/admin-graphql/2026-10/objects/DraftOrder
- Input objects:
  - https://shopify.dev/docs/api/admin-graphql/2026-10/input-objects/ShippingLineInput
  - https://shopify.dev/docs/api/admin-graphql/2026-10/input-objects/MailingAddressInput
  - https://shopify.dev/docs/api/admin-graphql/2026-10/input-objects/PaymentTermsInput
- Payment terms:
  - https://shopify.dev/docs/api/admin-graphql/2026-10/queries/paymentTermsTemplates
  - https://help.shopify.com/en/manual/fulfillment/managing-orders/payments/deferred-payments
- Variants:
  - https://shopify.dev/docs/api/admin-graphql/2026-10/objects/ProductVariant
  - https://shopify.dev/docs/api/admin-graphql/2026-10/scalars/Money
- Search syntax:
  - https://shopify.dev/docs/api/admin-graphql/2026-10/queries/draftOrders
  - https://shopify.dev/docs/api/admin-graphql/2026-10/queries/orders
  - https://shopify.dev/docs/api/usage/search-syntax
- Rate limits and errors:
  - https://shopify.dev/docs/apps/build/apis/graphql-admin/rate-limits
  - https://shopify.dev/docs/api/admin-graphql
  - https://shopify.dev/docs/api/usage/limits
- Customer Account API:
  - https://shopify.dev/docs/api/customer/latest
  - https://shopify.dev/docs/storefronts/headless/building-with-the-customer-account-api/getting-started
- Taxes: https://help.shopify.com/en/manual/taxes/include-exclude-taxes
- UAE province codes:
  https://github.com/Shopify/worldwide/blob/main/data/regions/AE.yml
- Vercel:
  - https://vercel.com/docs/functions/runtimes/node-js
  - https://vercel.com/docs/functions/configuring-functions/region
  - https://vercel.com/docs/project-configuration/vercel-json
  - https://vercel.com/docs/deployments/vercel-ignore
