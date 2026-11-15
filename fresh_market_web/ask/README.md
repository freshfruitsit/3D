# Ask assistant for the Shopify theme

The "Ask" assistant from the Fresh Market app, for the website. It follows the same script as the app. There is no AI and no server: it reads the store's own Ajax endpoints (`/search/suggest.json`, `/collections/…/products.json`, `/products/….js`, `/cart.js`, and `cart/add|change|clear.js`) and never places an order.

| File | What it is |
| --- | --- |
| `assets/fm-ask-brain.js` | The script, ported from the app. It sets `window.FMAskBrain`. |
| `assets/fm-ask.js` | The pill, the panel and the store adapter. It sets `window.FMAsk` and keeps the theme's cart icon, drawer and header count in sync. |
| `assets/fm-ask.css` | Styles, all scoped to `#fm-ask`, `#fm-ask-pill` and `#fm-ask-scrim`. |
| `sections/fm-ask.liquid` | The section. It outputs the config JSON and loads the three assets with `defer`. |
| `test/*.test.js` | Node tests that use fictional data. |

## Install

1. In the theme's code editor, create these four files and paste in the contents of the files here:
   - `assets/fm-ask-brain.js`
   - `assets/fm-ask.js`
   - `assets/fm-ask.css`
   - `sections/fm-ask.liquid`
2. Add the section to the footer group, so it shows on every page. Use one of these two ways:
   - **Theme editor:** go to Customize, then Footer, then Add section, and pick "Ask assistant". Save.
   - **Code:** in `sections/footer-group.json`, add the section and put its key last in `order`:

     ```json
     "sections": {
       "…existing sections…": {},
       "fm_ask": { "type": "fm-ask", "settings": { "enabled": true } }
     },
     "order": ["…existing keys…", "fm_ask"]
     ```

   `layout/theme.liquid` already renders `{% sections 'footer-group' %}`, so no layout change is needed.
3. Check the settings: button label, title, greeting, placeholder, footer note, and the customer-care phone and email.

To turn the assistant off, untick "Show the Ask assistant" in the section settings, or remove the section.

## Test

```sh
node --test fresh_market_web/ask/test/*.test.js
```

Use the glob. Node 22 does not take a directory argument here.
