/*
 * Fresh Market "Ask" assistant for the Shopify theme: the chat UI and the
 * Shopify storefront adapter the scripted brain (fm-ask-brain.js) talks to.
 * No AI and no server: the brain is scripted, the data comes from the
 * store's public storefront endpoints. Plain ES2018, no build step.
 *
 * Lazy: on page load only the pill button is created. The panel, the brain
 * and every network request wait for the first open.
 * Store text is always written with textContent / createElement, never
 * innerHTML.
 */
(function (root, factory) {
  var api = factory(root);
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root && root.document) {
    root.FMAsk = api;
    if (root.document.readyState === 'loading') root.document.addEventListener('DOMContentLoaded', api.boot);
    else api.boot();
  }
})(typeof window !== 'undefined' ? window : null, function (win) {
  'use strict';

  var DELIVERY_KEY = 'tfm-delivery-v1';
  var EMIRATES = { dubai: 'Dubai', auh: 'Abu Dhabi', shj: 'Sharjah', ajm: 'Ajman', uaq: 'Umm Al Quwain', rak: 'Ras Al Khaimah', fuj: 'Fujairah' };
  var UAE_UTC_OFFSET_MIN = 240;
  var NETWORK_ERROR = 'I could not reach the store. Check your connection and try again.';

  // [id, tile label, what the customer "says", icon]
  var OPTIONS = [
    ['offers', 'Today’s offers', 'What is on offer?', '🏷️'],
    ['categories', 'Categories', 'Show all categories', '▦'],
    ['recipes', 'Recipe ideas', 'Recipe ideas', '🍳'],
    ['local', 'Local UAE', 'Show local UAE produce', '🇦🇪'],
    ['gifts', 'Gifts & flowers', 'Gift ideas', '🎁'],
    ['bestsellers', 'Best sellers', 'What is popular?', '📈'],
    ['cart', 'My cart', 'Open my cart', '🛒'],
    ['care', 'Customer care', 'Contact customer service', '🎧']
  ];
  var DEFAULT_SUGGESTIONS = ['What is on offer?', 'Show me berries', 'Add 2 cucumbers', 'Ideas for a fruit salad',
    'Cheapest avocado', 'Show local UAE produce', 'Gift ideas', 'Is Express open?', 'Open my cart'];

  /* ------------------------------------------------------------------ */
  /* Pure helpers (exported for tests)                                   */
  /* ------------------------------------------------------------------ */

  // Storefront prices: numbers are already minor units (fils); strings are AED ("11.50").
  function toFils(v) {
    if (v === null || v === undefined || v === '') return null;
    if (typeof v === 'number') return isFinite(v) ? Math.round(v) : null;
    var n = parseFloat(String(v).replace(/,/g, ''));
    return isFinite(n) ? Math.round(n * 100) : null;
  }

  function formatAED(fils) {
    var n = Number(fils);
    if (!isFinite(n)) return '';
    return 'AED ' + (n / 100).toFixed(2);
  }

  var SIZE_RE = /(?:^|[^\w.])(\d+(?:[.,]\d+)?)\s?(kg|kgs|g|gm|gms|grams?|ml|ltr|l|litres?|liters?|pcs|pc|pieces?)(?![a-z])/i;
  var UNIT = { kg: 'kg', kgs: 'kg', g: 'g', gm: 'g', gms: 'g', gram: 'g', grams: 'g', ml: 'ml', ltr: 'L', l: 'L', litre: 'L', litres: 'L', liter: 'L', liters: 'L', pc: 'pcs', pcs: 'pcs', piece: 'pcs', pieces: 'pcs' };

  function sizeOf(title, handle) {
    var m = SIZE_RE.exec(String(title || '')) || SIZE_RE.exec(String(handle || '').replace(/-/g, ' '));
    if (!m) return null;
    return m[1].replace(',', '.') + ' ' + UNIT[m[2].toLowerCase()];
  }

  function tagList(tags) {
    if (Array.isArray(tags)) return tags.map(String);
    if (typeof tags === 'string' && tags) return tags.split(',').map(function (t) { return t.trim(); }).filter(Boolean);
    return [];
  }

  function originOf(tags) {
    var list = tagList(tags);
    for (var i = 0; i < list.length; i++) {
      var m = /^origin\s*:\s*(.+)$/i.exec(list[i]);
      if (m) return m[1].trim();
    }
    return null;
  }

  function subtitleOf(title, handle, tags) {
    return [sizeOf(title, handle), originOf(tags)].filter(Boolean).join(' · ');
  }

  function imageUrl(src, width) {
    if (!src) return '';
    var s = String(typeof src === 'object' ? (src.src || src.url || '') : src);
    if (s.indexOf('//') === 0) s = 'https:' + s;
    if (!/^https:\/\//i.test(s)) return '';
    return s + (s.indexOf('?') < 0 ? '?' : '&') + 'width=' + (width || 120);
  }

  // Only http(s), tel:, mailto: and same-site paths ever reach an href or location.
  function safeUrl(u) {
    if (typeof u !== 'string') return null;
    var s = u.trim();
    if (!s) return null;
    if (/^(https?:|mailto:|tel:)/i.test(s)) return s;
    if (s.charAt(0) === '/' && s.charAt(1) !== '/' && s.charAt(1) !== '\\') return s;
    return null;
  }

  function normRoot(r) {
    var s = String(r || '/');
    if (s.charAt(0) !== '/') s = '/' + s;
    return s.charAt(s.length - 1) === '/' ? s : s + '/';
  }

  function clampInt(v, lo, hi, dflt) {
    var n = parseInt(v, 10);
    if (!isFinite(n)) n = dflt;
    return Math.max(lo, Math.min(hi, n));
  }

  function pickVariant(variants) {
    var list = Array.isArray(variants) ? variants : [];
    for (var i = 0; i < list.length; i++) if (list[i] && list[i].available) return list[i];
    return list[0] || null;
  }

  function compareAt(c, price) {
    return c !== null && price !== null && c > price ? c : null;
  }

  // /products/<handle>.js (prices in fils, image as //cdn url)
  function mapJsProduct(p, rootPath) {
    if (!p || !p.handle) return null;
    var v = pickVariant(p.variants);
    var price = toFils(v ? v.price : p.price);
    return {
      id: p.id,
      variantId: v ? v.id : null,
      handle: p.handle,
      title: String(p.title || ''),
      subtitle: subtitleOf(p.title, p.handle, p.tags),
      priceFils: price,
      compareAtFils: compareAt(toFils(v ? v.compare_at_price : p.compare_at_price), price),
      available: v ? !!v.available : !!p.available,
      image: imageUrl(p.featured_image || (Array.isArray(p.images) && p.images[0])),
      url: normRoot(rootPath) + 'products/' + encodeURIComponent(p.handle),
      tags: tagList(p.tags),
      vendor: String(p.vendor || '')
    };
  }

  // /collections/<handle>/products.json (prices as "18.95" strings)
  function mapJsonProduct(p, rootPath) {
    if (!p || !p.handle) return null;
    var v = pickVariant(p.variants);
    var price = toFils(v ? v.price : null);
    var img = (Array.isArray(p.images) && p.images[0]) || (v && v.featured_image) || null;
    return {
      id: p.id,
      variantId: v ? v.id : null,
      handle: p.handle,
      title: String(p.title || ''),
      subtitle: subtitleOf(p.title, p.handle, p.tags),
      priceFils: price,
      compareAtFils: compareAt(toFils(v ? v.compare_at_price : null), price),
      available: !!(v && v.available),
      image: imageUrl(img),
      url: normRoot(rootPath) + 'products/' + encodeURIComponent(p.handle),
      tags: tagList(p.tags),
      vendor: String(p.vendor || '')
    };
  }

  // /search/suggest.json product (no variants): used only if /products/<handle>.js fails.
  function mapSuggestProduct(p, rootPath) {
    if (!p || !p.handle) return null;
    var price = toFils(p.price);
    return {
      id: p.id,
      variantId: null,
      handle: p.handle,
      title: String(p.title || ''),
      subtitle: subtitleOf(p.title, p.handle, p.tags),
      priceFils: price,
      compareAtFils: compareAt(toFils(p.compare_at_price_min), price),
      available: !!p.available,
      image: imageUrl(p.image || (p.featured_image && p.featured_image.url)),
      url: normRoot(rootPath) + 'products/' + encodeURIComponent(p.handle),
      tags: tagList(p.tags),
      vendor: String(p.vendor || '')
    };
  }

  function mapCart(c) {
    c = c || {};
    return {
      items: (c.items || []).map(function (i) {
        return {
          key: i.key,
          variantId: i.variant_id,
          title: String(i.product_title || i.title || ''),
          quantity: i.quantity,
          lineFils: toFils(i.final_line_price != null ? i.final_line_price : i.line_price)
        };
      }),
      itemCount: c.item_count || 0,
      totalFils: toFils(c.total_price) || 0
    };
  }

  // Hour of day in the UAE (UTC+4, no DST), as the theme's delivery script computes it.
  function uaeHour(date) {
    return ((date.getUTCHours() * 60 + date.getUTCMinutes() + UAE_UTC_OFFSET_MIN) % 1440) / 60;
  }

  /*
   * Delivery state, read the way the theme's tfm-delivery.js keeps it:
   *  - area + mode: localStorage "tfm-delivery-v1" = {mode, area:{name, em, lat, lng}}
   *    (the body also carries .tfm-mode-express while Express is chosen);
   *  - opening hours: the JSON in [data-tfm-delivery-config] (expressOpen/expressClose, UAE time);
   *  - promises: the texts the script renders into [data-tfm-market-sub] / [data-tfm-express-sub];
   *  - Express coverage: the Express mode button gets .is-off when the area is outside the radius.
   */
  function readDelivery(doc, storage, now, search) {
    var out = { area: null, emirate: null, mode: null, expressOpen: null, expressAvailableHere: null, promiseMarket: null, promiseExpress: null };
    var cfgEl = doc && doc.querySelector('[data-tfm-delivery-config]');
    var cfg = null;
    if (cfgEl) { try { cfg = JSON.parse(cfgEl.textContent); } catch (e) { cfg = null; } }
    var saved = null;
    try { saved = storage ? JSON.parse(storage.getItem(DELIVERY_KEY) || 'null') : null; } catch (e) { saved = null; }
    var area = saved && saved.area && typeof saved.area.name === 'string' && EMIRATES[saved.area.em] &&
      isFinite(saved.area.lat) && isFinite(saved.area.lng) ? saved.area : null;
    if (area) { out.area = area.name; out.emirate = EMIRATES[area.em]; }
    var bodyExpress = !!(doc && doc.body && doc.body.classList.contains('tfm-mode-express'));
    if (cfg || saved) out.mode = bodyExpress || (saved && saved.mode === 'express') ? 'express' : 'market';
    if (cfg) {
      var open = parseFloat(cfg.expressOpen), close = parseFloat(cfg.expressClose);
      if (isFinite(open) && isFinite(close)) {
        var t = search ? parseFloat(new URLSearchParams(search).get('tfm_time')) : NaN;
        var h = isFinite(t) ? t : uaeHour(now);
        out.expressOpen = h >= open && h < close;
      }
    }
    if (area && cfg && cfg.hub) {
      var km = distanceKm(area, { lat: parseFloat(cfg.hub.lat), lng: parseFloat(cfg.hub.lng) });
      var limit = parseFloat(cfg.expressKm);
      if (isFinite(km) && isFinite(limit)) out.expressAvailableHere = km <= limit;
    }
    // The header texts are only trusted once the script has drawn them for this area.
    var where = doc ? doc.querySelector('[data-tfm-chip-where]') : null;
    if (area && where && where.textContent.trim() === area.name) {
      var mk = doc.querySelector('[data-tfm-market-sub]');
      var ex = doc.querySelector('[data-tfm-express-sub]');
      if (mk && mk.textContent.trim()) out.promiseMarket = mk.textContent.trim();
      if (ex && ex.textContent.trim() && out.expressAvailableHere !== false) out.promiseExpress = ex.textContent.trim();
    }
    return out;
  }

  // Same great-circle distance as tfm-delivery.js.
  function distanceKm(a, b) {
    var r = function (x) { return x * Math.PI / 180; };
    var dLat = r(a.lat - b.lat), dLng = r(a.lng - b.lng);
    var s = Math.pow(Math.sin(dLat / 2), 2) + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.pow(Math.sin(dLng / 2), 2);
    return 6371 * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
  }

  /* ------------------------------------------------------------------ */
  /* Theme bridge: tell the Horizon-based theme the cart changed          */
  /* ------------------------------------------------------------------ */

  /*
   * The theme (Horizon + tfm.js) listens for Shopify's standard
   * CartLinesUpdateEvent ("@shopify/events" in the import map):
   * cart-icon re-renders its bubble from cart.totalQuantity,
   * cart-items-component morphs the drawer from detail.sections[sectionId]
   * (Section Rendering API, sent with the cart request). tfm.js's own header
   * counter [data-tfm-cart-count] is set directly, as tfm.js does.
   */
  function createThemeBridge(doc, sourceEl) {
    var eventsPromise = null;
    function loadEvents() {
      if (!eventsPromise) {
        eventsPromise = new Promise(function (resolve) {
          var imp = null;
          try { imp = new Function('s', 'return import(s)'); } catch (e) { imp = null; }
          if (!imp) return resolve(null);
          var done = false;
          var timer = setTimeout(function () { if (!done) { done = true; resolve(null); } }, 4000);
          imp('@shopify/events').then(function (mod) {
            if (!done) { done = true; clearTimeout(timer); resolve(mod && mod.CartLinesUpdateEvent ? mod : null); }
          }, function () { if (!done) { done = true; clearTimeout(timer); resolve(null); } });
        });
      }
      return eventsPromise;
    }
    function sectionIds() {
      if (!doc) return [];
      var ids = [];
      var els = doc.querySelectorAll('cart-items-component[data-section-id]');
      for (var i = 0; i < els.length; i++) {
        var id = els[i].getAttribute('data-section-id');
        if (id && ids.indexOf(id) < 0) ids.push(id);
      }
      return ids;
    }
    function updateCounts(count) {
      if (!doc) return;
      var els = doc.querySelectorAll('[data-tfm-cart-count]');
      for (var i = 0; i < els.length; i++) els[i].textContent = String(count);
      var btns = doc.querySelectorAll('[data-tfm-open-cart][aria-label^="Cart"]');
      for (var j = 0; j < btns.length; j++) btns[j].setAttribute('aria-label', 'Cart, ' + count + (count === 1 ? ' item' : ' items'));
      try { win.sessionStorage.setItem('cart-count', JSON.stringify({ value: String(count), timestamp: Date.now() })); } catch (e) { /* private mode */ }
    }
    // request() -> Promise<{ok, data, cart (raw /cart.js), sections}>
    function run(action, context, lines, request) {
      return loadEvents().then(function (mod) {
        var Ev = mod && mod.CartLinesUpdateEvent;
        var deferred = null;
        if (Ev && typeof Ev.createPromise === 'function') {
          try {
            deferred = Ev.createPromise();
            (sourceEl() || doc).dispatchEvent(new Ev({ action: action, context: context, lines: lines, promise: deferred.promise }));
          } catch (e) { deferred = null; }
        }
        return request().then(function (res) {
          if (res.cart) {
            if (deferred) {
              try {
                deferred.resolve({
                  cart: Ev.createCartFromAjaxResponse(res.cart),
                  detail: { items: res.cart.items, source: 'fm-ask', sourceId: 'fm-ask', itemCount: res.cart.item_count, sections: res.sections || undefined, didError: !res.ok }
                });
              } catch (e) { deferred.reject(e); }
            }
            updateCounts(res.cart.item_count);
          } else if (deferred) {
            deferred.reject(new Error('cart unavailable'));
          }
          return res;
        }, function (err) {
          if (deferred) deferred.reject(err);
          throw err;
        });
      });
    }
    return { run: run, sectionIds: sectionIds, updateCounts: updateCounts, loadEvents: loadEvents };
  }

  /* ------------------------------------------------------------------ */
  /* Store adapter (the only thing the brain calls)                       */
  /* ------------------------------------------------------------------ */

  function createStore(opts) {
    opts = opts || {};
    var fetchFn = opts.fetch || (win && win.fetch ? win.fetch.bind(win) : null);
    var rootPath = normRoot(opts.root || (win && win.Shopify && win.Shopify.routes && win.Shopify.routes.root) || '/');
    var doc = opts.document !== undefined ? opts.document : (win ? win.document : null);
    var storage = opts.storage;
    if (storage === undefined) { try { storage = win ? win.localStorage : null; } catch (e) { storage = null; } }
    var now = opts.now || function () { return new Date(); };
    var bridge = opts.bridge || { run: function (a, c, l, request) { return request(); }, sectionIds: function () { return []; } };
    var productCache = {};
    var collectionsCache = null;

    function request(path, body) {
      var headers = { Accept: 'application/json' };
      if (body) headers['Content-Type'] = 'application/json';
      return fetchFn(rootPath + path, {
        method: body ? 'POST' : 'GET',
        headers: headers,
        credentials: 'same-origin',
        body: body ? JSON.stringify(body) : undefined
      }).then(function (r) {
        return r.json().then(function (d) { return d; }, function () { return null; })
          .then(function (data) { return { ok: r.ok, status: r.status, data: data }; });
      });
    }
    function getData(path) {
      return request(path).then(function (res) {
        if (!res.ok) { var e = new Error('HTTP ' + res.status); e.status = res.status; throw e; }
        return res.data;
      });
    }
    function rawCart() { return getData('cart.js'); }

    // POST a cart mutation with the drawer's sections, then read the cart back for the theme.
    function mutate(path, body, action, context, lines) {
      var ids = bridge.sectionIds();
      if (ids.length) { body.sections = ids.join(','); body.sections_url = (win && win.location ? win.location.pathname : '/'); }
      return bridge.run(action, context, lines, function () {
        return request(path, body).then(function (res) {
          return rawCart().then(function (cart) {
            return { ok: res.ok, data: res.data, cart: cart, sections: res.ok && res.data ? res.data.sections : null };
          }, function () { return { ok: res.ok, data: res.data, cart: null, sections: null }; });
        });
      }).then(function (res) {
        if (res.ok) return { ok: true };
        var d = res.data || {};
        return { ok: false, error: String(d.description || d.message || 'The cart could not be updated.') };
      }, function () {
        return { ok: false, error: NETWORK_ERROR };
      });
    }

    var store = {
      search: function (query, limit) {
        var n = clampInt(limit, 1, 10, 6);
        var q = String(query || '').trim();
        if (!q) return Promise.resolve([]);
        return getData('search/suggest.json?q=' + encodeURIComponent(q) +
          '&resources%5Btype%5D=product&resources%5Blimit%5D=' + n +
          '&resources%5Boptions%5D%5Bunavailable_products%5D=last')
          .then(function (d) {
            var list = (d && d.resources && d.resources.results && d.resources.results.products) || [];
            return Promise.all(list.slice(0, n).map(function (s) {
              return store.product(s.handle).then(function (p) { return p || mapSuggestProduct(s, rootPath); },
                function () { return mapSuggestProduct(s, rootPath); });
            }));
          })
          .then(function (arr) { return arr.filter(Boolean); });
      },
      collection: function (handle, limit) {
        var n = clampInt(limit, 1, 250, 12);
        if (!handle) return Promise.resolve([]);
        return getData('collections/' + encodeURIComponent(handle) + '/products.json?limit=' + n)
          .then(function (d) {
            return ((d && d.products) || []).map(function (p) { return mapJsonProduct(p, rootPath); }).filter(Boolean);
          }, function (e) { if (e && e.status === 404) return []; throw e; });
      },
      collections: function () {
        if (!collectionsCache) {
          collectionsCache = getData('collections.json?limit=250').then(function (d) {
            return ((d && d.collections) || [])
              .filter(function (c) { return c && c.handle && (c.products_count == null || c.products_count > 0); })
              .map(function (c) { return { handle: c.handle, title: String(c.title || c.handle) }; });
          });
          collectionsCache.catch(function () { collectionsCache = null; });
        }
        return collectionsCache;
      },
      product: function (handle) {
        if (!handle) return Promise.resolve(null);
        var key = String(handle);
        if (!productCache[key]) {
          productCache[key] = getData('products/' + encodeURIComponent(key) + '.js')
            .then(function (p) { return mapJsProduct(p, rootPath); },
              function (e) { if (e && e.status === 404) return null; throw e; });
          productCache[key].catch(function () { delete productCache[key]; });
        }
        return productCache[key];
      },
      cart: function () { return rawCart().then(mapCart); },
      add: function (variantId, quantity) {
        var q = clampInt(quantity, 1, 99, 1);
        if (variantId === null || variantId === undefined || variantId === '') return Promise.resolve({ ok: false, error: 'This product cannot be added here.' });
        var id = /^\d+$/.test(String(variantId)) ? Number(variantId) : variantId;
        return mutate('cart/add.js', { items: [{ id: id, quantity: q }] }, 'add', 'product',
          [{ merchandiseId: String(variantId), quantity: q }]);
      },
      setQuantity: function (key, quantity) {
        var q = clampInt(quantity, 0, 999, 0);
        if (!key) return Promise.resolve({ ok: false, error: 'That item is not in your cart.' });
        return mutate('cart/change.js', { id: String(key), quantity: q }, q > 0 ? 'update' : 'remove', 'cart',
          [{ id: String(key), quantity: q }]);
      },
      clear: function () {
        return rawCart().then(function (c) { return (c && c.items) || []; }, function () { return []; })
          .then(function (items) {
            return mutate('cart/clear.js', {}, 'remove', 'cart',
              items.map(function (i) { return { id: String(i.key), quantity: 0 }; }));
          })
          .then(function (r) { return r.ok ? { ok: true } : r; });
      },
      delivery: function () {
        return Promise.resolve(readDelivery(doc, storage, now(), win && win.location ? win.location.search : ''));
      }
    };
    return store;
  }

  /* ------------------------------------------------------------------ */
  /* UI                                                                  */
  /* ------------------------------------------------------------------ */

  var SVG_NS = 'http://www.w3.org/2000/svg';
  var ICONS = {
    spark: 'M12 2.5c.5 4.6 2.4 7 7 7.5v.1c-4.6.5-6.5 2.9-7 7.4h-.1c-.5-4.5-2.4-6.9-7-7.4V10c4.6-.5 6.5-2.9 7-7.5Z',
    close: 'M6.4 5 5 6.4 10.6 12 5 17.6 6.4 19l5.6-5.6 5.6 5.6 1.4-1.4-5.6-5.6L19 6.4 17.6 5 12 10.6Z',
    send: 'M11 20V7.8l-5.6 5.6L4 12l8-8 8 8-1.4 1.4L13 7.8V20Z',
    plus: 'M11 5h2v6h6v2h-6v6h-2v-6H5v-2h6Z',
    minus: 'M5 11h14v2H5Z'
  };

  function svgIcon(doc, name, size) {
    var s = doc.createElementNS(SVG_NS, 'svg');
    s.setAttribute('viewBox', '0 0 24 24');
    s.setAttribute('width', String(size || 20));
    s.setAttribute('height', String(size || 20));
    s.setAttribute('aria-hidden', 'true');
    s.setAttribute('focusable', 'false');
    var p = doc.createElementNS(SVG_NS, 'path');
    p.setAttribute('d', ICONS[name]);
    p.setAttribute('fill', 'currentColor');
    s.appendChild(p);
    return s;
  }

  function readConfig(doc) {
    var el = doc.getElementById('fm-ask-config');
    var cfg = {};
    if (el) { try { cfg = JSON.parse(el.textContent) || {}; } catch (e) { cfg = {}; } }
    function str(k, d) { return typeof cfg[k] === 'string' && cfg[k].trim() ? cfg[k].trim() : d; }
    return {
      enabled: cfg.enabled !== false,
      buttonLabel: str('buttonLabel', 'Ask'),
      buttonSub: str('buttonSub', 'Find anything fast'),
      title: str('title', 'Ask Fresh Market'),
      subtitle: str('subtitle', 'Find products, offers, delivery times'),
      greeting: str('greeting', 'Hi! I can find products, add them to your cart, show today’s offers and tell you when we can deliver. What do you need?'),
      placeholder: str('placeholder', 'Ask for a product or a category'),
      footer: str('footer', 'Answers come from the Fresh Market catalogue'),
      contactPhone: str('contactPhone', ''),
      contactEmail: str('contactEmail', ''),
      storeName: str('storeName', 'Fresh Market'),
      root: str('root', '')
    };
  }

  function createUI(w, cfg, deps) {
    var doc = w.document;
    var html = doc.documentElement;
    var mqDesktop = w.matchMedia ? w.matchMedia('(min-width: 750px)') : null;
    var ui = { pill: null, panel: null, scrim: null, body: null, chips: null, input: null, go: null, live: null };
    var state = { built: false, open: false, busy: false, opener: null, brain: null, store: null, cartMap: {}, rows: [], cartLoaded: null, greeted: false };

    function el(tag, cls, text) {
      var e = doc.createElement(tag);
      if (cls) e.className = cls;
      if (text !== undefined && text !== null) e.textContent = String(text);
      return e;
    }

    /* ---- pill ---- */
    function makePill() {
      if (doc.getElementById('fm-ask-pill')) return doc.getElementById('fm-ask-pill');
      var b = el('button');
      b.id = 'fm-ask-pill';
      b.type = 'button';
      b.setAttribute('aria-haspopup', 'dialog');
      b.setAttribute('aria-expanded', 'false');
      b.setAttribute('aria-controls', 'fm-ask');
      var sp = el('span', 'fm-ask-pill__sp');
      sp.appendChild(svgIcon(doc, 'spark', 18));
      var tx = el('span', 'fm-ask-pill__tx', cfg.buttonLabel);
      tx.appendChild(el('span', 'fm-ask-pill__sub', cfg.buttonSub));
      b.appendChild(sp);
      b.appendChild(tx);
      b.addEventListener('click', function () { open(b); });
      doc.body.appendChild(b);
      return b;
    }

    /* ---- panel (built on first open) ---- */
    function build() {
      ui.scrim = el('div');
      ui.scrim.id = 'fm-ask-scrim';
      ui.scrim.addEventListener('click', close);

      var p = el('div');
      p.id = 'fm-ask';
      p.setAttribute('role', 'dialog');
      p.setAttribute('aria-modal', 'true');
      p.setAttribute('aria-labelledby', 'fm-ask-title');
      p.setAttribute('aria-describedby', 'fm-ask-sub');
      p.tabIndex = -1;

      var hd = el('div', 'fm-ask-hd');
      var av = el('div', 'fm-ask-av');
      av.appendChild(svgIcon(doc, 'spark', 22));
      var ht = el('div', 'fm-ask-ht');
      var h = el('h2', 'fm-ask-title', cfg.title);
      h.id = 'fm-ask-title';
      var sub = el('p', 'fm-ask-sub', cfg.subtitle);
      sub.id = 'fm-ask-sub';
      ht.appendChild(h);
      ht.appendChild(sub);
      var x = el('button', 'fm-ask-x');
      x.type = 'button';
      x.setAttribute('aria-label', 'Close');
      x.appendChild(svgIcon(doc, 'close', 20));
      x.addEventListener('click', close);
      hd.appendChild(av);
      hd.appendChild(ht);
      hd.appendChild(x);

      ui.body = el('div', 'fm-ask-body');
      ui.live = el('div', 'fm-ask-sr');
      ui.live.setAttribute('aria-live', 'polite');
      ui.live.setAttribute('aria-atomic', 'true');
      ui.chips = el('div', 'fm-ask-chips');
      ui.chips.setAttribute('role', 'group');
      ui.chips.setAttribute('aria-label', 'Suggestions');

      var form = el('form', 'fm-ask-form');
      form.setAttribute('role', 'search');
      var label = el('label', 'fm-ask-sr', 'Ask a question');
      label.htmlFor = 'fm-ask-input';
      ui.input = el('input', 'fm-ask-input');
      ui.input.id = 'fm-ask-input';
      ui.input.type = 'text';
      ui.input.autocomplete = 'off';
      ui.input.maxLength = 200;
      ui.input.placeholder = cfg.placeholder;
      ui.input.setAttribute('enterkeyhint', 'send');
      ui.go = el('button', 'fm-ask-go');
      ui.go.type = 'submit';
      ui.go.setAttribute('aria-label', 'Send');
      ui.go.appendChild(svgIcon(doc, 'send', 20));
      form.appendChild(label);
      form.appendChild(ui.input);
      form.appendChild(ui.go);
      form.addEventListener('submit', function (e) {
        e.preventDefault();
        var text = ui.input.value.trim();
        if (!text || state.busy) return;
        ui.input.value = '';
        send({ text: text }, text);
      });

      var ft = el('p', 'fm-ask-ft', cfg.footer);

      p.appendChild(hd);
      p.appendChild(ui.body);
      p.appendChild(ui.live);
      p.appendChild(ui.chips);
      p.appendChild(form);
      p.appendChild(ft);
      p.addEventListener('keydown', onKeydown);
      ui.panel = p;
      doc.body.appendChild(ui.scrim);
      doc.body.appendChild(p);

      state.store = deps.store();
      var Brain = w.FMAskBrain;
      try {
        state.brain = Brain && typeof Brain.create === 'function'
          ? Brain.create(state.store, { contactPhone: cfg.contactPhone, contactEmail: cfg.contactEmail, storeName: cfg.storeName, greeting: cfg.greeting })
          : null;
      } catch (e) { state.brain = null; }
      state.built = true;
    }

    function focusables() {
      var list = ui.panel.querySelectorAll('button:not([disabled]), a[href], input:not([disabled]), [tabindex]:not([tabindex="-1"])');
      var out = [];
      for (var i = 0; i < list.length; i++) if (list[i].offsetWidth || list[i].offsetHeight || list[i].getClientRects().length) out.push(list[i]);
      return out;
    }

    function onKeydown(e) {
      if (e.key === 'Escape' || e.key === 'Esc') { e.preventDefault(); close(); return; }
      if (e.key !== 'Tab') return;
      var f = focusables();
      if (!f.length) { e.preventDefault(); ui.panel.focus(); return; }
      var first = f[0], last = f[f.length - 1], active = doc.activeElement;
      if (e.shiftKey && (active === first || active === ui.panel)) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && active === last) { e.preventDefault(); first.focus(); }
    }

    // Keep focus inside while open (e.g. a click on the page behind on desktop).
    function onFocusIn(e) {
      if (state.open && ui.panel && !ui.panel.contains(e.target)) ui.panel.focus();
    }

    function open(opener) {
      if (state.open) return;
      if (!state.built) build();
      state.opener = opener || doc.activeElement;
      state.open = true;
      html.classList.add('fm-ask-is-open');
      if (ui.pill) ui.pill.setAttribute('aria-expanded', 'true');
      doc.addEventListener('focusin', onFocusIn);
      if (!state.greeted) {
        state.greeted = true;
        addBot(cfg.greeting);
        if (state.brain) ui.body.appendChild(optionsGrid());
        else addBot('The assistant is not available right now. Please try again later.');
        setChips(DEFAULT_SUGGESTIONS);
        state.cartLoaded = refreshCart();
      }
      var target = mqDesktop && mqDesktop.matches ? ui.input : ui.panel;
      setTimeout(function () { try { target.focus({ preventScroll: true }); } catch (e) { target.focus(); } }, 30);
    }

    function close() {
      if (!state.open) return;
      state.open = false;
      html.classList.remove('fm-ask-is-open');
      if (ui.pill) ui.pill.setAttribute('aria-expanded', 'false');
      doc.removeEventListener('focusin', onFocusIn);
      var back = state.opener && doc.contains(state.opener) ? state.opener : ui.pill;
      if (back && back.focus) { try { back.focus({ preventScroll: true }); } catch (e) { back.focus(); } }
    }

    function announce(text) {
      if (!ui.live) return;
      ui.live.textContent = '';
      setTimeout(function () { ui.live.textContent = text; }, 60);
    }

    function addBot(text) {
      var b = el('div', 'fm-ask-bot', text);
      ui.body.appendChild(b);
      return b;
    }

    function addMe(text) {
      var b = el('div', 'fm-ask-me', text);
      ui.body.appendChild(b);
      ui.body.scrollTop = ui.body.scrollHeight;
      return b;
    }

    function optionsGrid() {
      var g = el('div', 'fm-ask-grid');
      g.setAttribute('role', 'group');
      g.setAttribute('aria-label', 'Quick options');
      OPTIONS.forEach(function (o) {
        var b = el('button', 'fm-ask-opt');
        b.type = 'button';
        b.setAttribute('data-option', o[0]);
        var ic = el('i', 'fm-ask-opt__ic', o[3]);
        ic.setAttribute('aria-hidden', 'true');
        b.appendChild(ic);
        b.appendChild(el('span', '', o[1]));
        b.addEventListener('click', function () { send({ option: o[0] }, o[2]); });
        g.appendChild(b);
      });
      return g;
    }

    function setChips(list) {
      ui.chips.textContent = '';
      (list || []).slice(0, 10).forEach(function (t) {
        if (typeof t !== 'string' || !t.trim()) return;
        var b = el('button', 'fm-ask-chip', t);
        b.type = 'button';
        b.addEventListener('click', function () { send({ chip: t }, t); });
        ui.chips.appendChild(b);
      });
      ui.chips.scrollLeft = 0;
    }

    function setBusy(on) {
      state.busy = on;
      ui.go.disabled = on;
      var btns = ui.panel.querySelectorAll('.fm-ask-opt, .fm-ask-chip');
      for (var i = 0; i < btns.length; i++) btns[i].disabled = on;
    }

    function send(input, echo) {
      if (state.busy) return;
      if (echo) addMe(echo);
      if (!state.brain) { addBot('The assistant is not available right now. Please try again later.'); return; }
      setBusy(true);
      var typing = el('div', 'fm-ask-bot fm-ask-typing');
      typing.setAttribute('role', 'img');
      typing.setAttribute('aria-label', 'The assistant is typing');
      typing.appendChild(el('i'));
      typing.appendChild(el('i'));
      typing.appendChild(el('i'));
      ui.body.appendChild(typing);
      ui.body.scrollTop = ui.body.scrollHeight;
      Promise.resolve()
        .then(function () { return state.brain.reply(input); })
        .then(function (r) { return r; }, function () { return { text: 'Sorry, something went wrong. Please try again.' }; })
        .then(function (r) {
          typing.remove();
          setBusy(false);
          return renderReply(r || { text: '' });
        });
    }

    function renderReply(r) {
      var first = null;
      if (r.text) first = addBot(r.text);
      if (Array.isArray(r.products) && r.products.length) {
        var list = el('div', 'fm-ask-list');
        r.products.forEach(function (p) { if (p) list.appendChild(productRow(p)); });
        ui.body.appendChild(list);
        first = first || list;
      }
      if (Array.isArray(r.links) && r.links.length) {
        var wrap = el('div', 'fm-ask-links');
        r.links.forEach(function (l) {
          var href = l && safeUrl(l.url);
          if (!href) return;
          var a = el('a', 'fm-ask-link', l.label || href);
          a.href = href;
          a.appendChild(el('span', '', ' ›')).setAttribute('aria-hidden', 'true');
          wrap.appendChild(a);
        });
        if (wrap.childNodes.length) ui.body.appendChild(wrap);
        first = first || wrap;
      }
      if (r.showOptions && state.brain) {
        var g = optionsGrid();
        ui.body.appendChild(g);
        first = first || g;
      }
      setChips(Array.isArray(r.suggestions) && r.suggestions.length ? r.suggestions : DEFAULT_SUGGESTIONS);
      if (first) ui.body.scrollTop = Math.max(0, first.offsetTop - ui.body.offsetTop - 12);
      var msg = r.text || '';
      if (Array.isArray(r.products) && r.products.length) msg += ' ' + r.products.length + (r.products.length === 1 ? ' product.' : ' products.');
      if (msg.trim()) announce(msg.trim());
      var after = r.cartChanged ? refreshCart() : (state.cartLoaded || Promise.resolve());
      var nav = r.navigate && safeUrl(r.navigate);
      if (nav) setTimeout(function () { w.location.assign(nav); }, 1200);
      return after;
    }

    /* ---- product rows ---- */
    function productRow(p) {
      var row = el('div', 'fm-ask-prod');
      var href = safeUrl(p.url);
      var media = el(href ? 'a' : 'div', 'fm-ask-prod__media');
      if (href) { media.href = href; media.tabIndex = -1; media.setAttribute('aria-hidden', 'true'); }
      var src = typeof p.image === 'string' && /^https:\/\//i.test(p.image) ? p.image : '';
      if (src) {
        var img = el('img');
        img.src = src;
        img.alt = '';
        img.loading = 'lazy';
        img.decoding = 'async';
        img.width = 52;
        img.height = 52;
        media.appendChild(img);
      }
      var info = el('div', 'fm-ask-prod__info');
      var t = el(href ? 'a' : 'span', 'fm-ask-prod__title', p.title);
      if (href) t.href = href;
      info.appendChild(t);
      if (p.subtitle) info.appendChild(el('span', 'fm-ask-prod__s', p.subtitle));
      var pr = el('div', 'fm-ask-prod__pr');
      var sale = p.compareAtFils && p.priceFils !== null && p.compareAtFils > p.priceFils;
      if (sale) pr.classList.add('is-sale');
      pr.appendChild(el('span', 'fm-ask-prod__now', formatAED(p.priceFils)));
      if (sale) {
        var was = el('s', 'fm-ask-prod__was');
        was.appendChild(el('span', 'fm-ask-sr', 'was '));
        was.appendChild(doc.createTextNode(formatAED(p.compareAtFils)));
        pr.appendChild(was);
      }
      var act = el('div', 'fm-ask-prod__act');
      row.appendChild(media);
      row.appendChild(info);
      row.appendChild(pr);
      row.appendChild(act);
      var rec = { p: p, act: act, pending: false };
      state.rows.push(rec);
      renderAction(rec, null);
      return row;
    }

    function renderAction(rec, focusWhich) {
      var p = rec.p, act = rec.act;
      act.textContent = '';
      if (!p.available) { act.appendChild(el('span', 'fm-ask-soldout', 'Sold out')); return; }
      if (p.variantId === null || p.variantId === undefined) {
        var href = safeUrl(p.url);
        if (href) { var v = el('a', 'fm-ask-view', 'View'); v.href = href; act.appendChild(v); }
        return;
      }
      var line = state.cartMap[String(p.variantId)];
      var focusEl = null;
      if (line && line.quantity > 0) {
        var st = el('div', 'fm-ask-stepper');
        var dec = el('button', 'fm-ask-step');
        dec.type = 'button';
        dec.setAttribute('aria-label', line.quantity === 1 ? 'Remove ' + p.title + ' from cart' : 'One less ' + p.title);
        dec.appendChild(svgIcon(doc, 'minus', 18));
        dec.addEventListener('click', function () { changeQty(rec, -1, 'dec'); });
        var q = el('span', 'fm-ask-qty', line.quantity);
        q.setAttribute('aria-label', line.quantity + ' in cart');
        var inc = el('button', 'fm-ask-step');
        inc.type = 'button';
        inc.setAttribute('aria-label', 'One more ' + p.title);
        inc.appendChild(svgIcon(doc, 'plus', 18));
        inc.addEventListener('click', function () { changeQty(rec, 1, 'inc'); });
        st.appendChild(dec);
        st.appendChild(q);
        st.appendChild(inc);
        act.appendChild(st);
        focusEl = focusWhich === 'dec' ? dec : (focusWhich ? inc : null);
      } else {
        var add = el('button', 'fm-ask-add');
        add.type = 'button';
        add.setAttribute('aria-label', 'Add ' + p.title + ' to cart');
        add.appendChild(svgIcon(doc, 'plus', 20));
        add.addEventListener('click', function () { changeQty(rec, 1, 'add'); });
        act.appendChild(add);
        focusEl = focusWhich ? add : null;
      }
      if (focusEl && state.open) focusEl.focus();
    }

    function changeQty(rec, delta, which) {
      if (rec.pending) return;
      rec.pending = true;
      rec.act.classList.add('is-busy');
      var line = state.cartMap[String(rec.p.variantId)];
      var op = line
        ? state.store.setQuantity(line.key, Math.max(0, line.quantity + delta))
        : state.store.add(rec.p.variantId, 1);
      var hadFocus = rec.act.contains(doc.activeElement);
      op.then(function (res) { return res; }, function () { return { ok: false, error: NETWORK_ERROR }; })
        .then(function (res) {
          return refreshCart(rec).then(function () {
            rec.pending = false;
            rec.act.classList.remove('is-busy');
            renderAction(rec, hadFocus ? which : null);
            var now = state.cartMap[String(rec.p.variantId)];
            if (res && res.ok) announce(now ? rec.p.title + ': ' + now.quantity + ' in your cart.' : rec.p.title + ' removed from your cart.');
            else {
              var b = addBot('Sorry, I could not update your cart. ' + ((res && res.error) || ''));
              ui.body.scrollTop = b.offsetTop - ui.body.offsetTop - 12;
              announce(b.textContent);
            }
          });
        });
    }

    // Reads the cart and redraws every product row (except `skip`, redrawn by its caller).
    function refreshCart(skip) {
      if (!state.store) return Promise.resolve();
      return state.store.cart().then(function (c) {
        var map = {};
        (c.items || []).forEach(function (i) {
          var k = String(i.variantId);
          if (!map[k]) map[k] = { key: i.key, quantity: i.quantity };
        });
        state.cartMap = map;
      }, function () { /* keep the last known state */ }).then(function () {
        state.rows.forEach(function (r) { if (r !== skip && !r.pending) renderAction(r, null); });
      });
    }

    return {
      mount: function () { ui.pill = makePill(); return ui.pill; },
      open: open,
      close: close,
      isOpen: function () { return state.open; },
      _state: state
    };
  }

  var booted = null;
  function boot() {
    if (booted || !win || !win.document || !win.document.body) return booted;
    var cfg = readConfig(win.document);
    if (!cfg.enabled) return null;
    var bridge = createThemeBridge(win.document, function () { return win.document.getElementById('fm-ask'); });
    booted = createUI(win, cfg, {
      store: function () { return createStore({ root: cfg.root || undefined, bridge: bridge }); }
    });
    booted.mount();
    // Theme links can open the assistant: <a href="#fm-ask" data-fm-ask-open>.
    win.document.addEventListener('click', function (e) {
      var t = e.target && e.target.closest ? e.target.closest('[data-fm-ask-open]') : null;
      if (t) { e.preventDefault(); booted.open(t); }
    });
    return booted;
  }

  return {
    boot: boot,
    open: function () { var u = boot(); if (u) u.open(); },
    close: function () { if (booted) booted.close(); },
    createStore: createStore,
    createThemeBridge: createThemeBridge,
    readDelivery: readDelivery,
    mapJsProduct: mapJsProduct,
    mapJsonProduct: mapJsonProduct,
    mapSuggestProduct: mapSuggestProduct,
    mapCart: mapCart,
    toFils: toFils,
    formatAED: formatAED,
    sizeOf: sizeOf,
    originOf: originOf,
    subtitleOf: subtitleOf,
    imageUrl: imageUrl,
    safeUrl: safeUrl,
    uaeHour: uaeHour,
    OPTIONS: OPTIONS
  };
});
