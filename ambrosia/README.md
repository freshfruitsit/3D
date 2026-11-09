# Ambrosia landing page

A standalone landing page for the **Ambrosia** collection
(<https://testtfm.myshopify.com/collections/ambrosia>) — Ambrosia is The Fresh
Market's own brand of hand-made fruit and flower arrangements.

`index.html` is self-contained: one file, no build step, no dependencies. Fonts
come from Google Fonts and every product photograph is loaded straight from the
store's own Shopify CDN, so the page stays visually in sync with the catalogue.

## What's on the page

| Section | Content |
| --- | --- |
| Hero | The collection's own line, "We Arrange Smiles", over the Queen of Sheba Royal Gourmet |
| The Ambrosia year | The six occasion groups ordered by the UAE calendar — Valentine's, Ramadan & Eid, Mother's Day, weddings, National Day, Christmas |
| Signature | The four Royal Gourmet showpieces |
| Catalogue | All 260 products, filterable by kind and occasion, searchable, sortable, 24 at a time |
| Quick look | Modal with the product shot, price, kind, occasions and a link to the store |
| Craft / Gifting / FAQ | Supporting copy |

Every product links to its real page at
`https://testtfm.myshopify.com/collections/ambrosia/products/<handle>`.

## The product data

The 260 products are embedded as a JSON array in the `<script>` block at the
bottom of `index.html`, pulled from the store on **9 November 2026** via:

```bash
curl -s "https://testtfm.myshopify.com/collections/ambrosia/products.json?limit=250&page=1"
```

Each row is `[name, handle, price, image, [alt images], occasionBits, kindBits, isNew]`.
Handles are stored without their shared `ambrosia-` prefix (a leading `!` marks
the seven that don't have it), and images without the shared CDN prefix.

**This is a snapshot.** Prices, availability and new arrivals will drift from the
store. To refresh, re-run the request above and regenerate the array. If the page
is moved onto the Shopify theme itself, the better option is to drop the array
and render the grid from Liquid (`collections.ambrosia.products`) so it is always
live.

## Using it

Open `index.html` in a browser, or serve the directory:

```bash
python3 -m http.server 8000
```

To put it on the store, paste the contents into a Shopify page template or a
custom section. The page sets no global styles outside its own `<style>` block,
but it does assume it owns the full width of the page.
