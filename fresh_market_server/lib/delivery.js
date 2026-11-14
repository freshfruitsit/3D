// The store's delivery rules, ported line for line from the Android app
// (fresh_market_app/lib/delivery/delivery_config.dart and
// delivery_rules.dart, which port the website's tfm-delivery.js). Keep the
// numbers and texts here in step with those files: the server recomputes the
// promise the app showed and refuses Express where the app would.

/** The seven emirates: the app's code -> display name and Shopify province code. */
export const EMIRATES = Object.freeze({
  dubai: { label: 'Dubai', province: 'DU' },
  auh: { label: 'Abu Dhabi', province: 'AZ' },
  shj: { label: 'Sharjah', province: 'SH' },
  ajm: { label: 'Ajman', province: 'AJ' },
  uaq: { label: 'Umm Al Quwain', province: 'UQ' },
  rak: { label: 'Ras Al Khaimah', province: 'RK' },
  fuj: { label: 'Fujairah', province: 'FU' },
});

/**
 * Shopify's province code for an emirate code (dubai -> DU, auh -> AZ,
 * shj -> SH, ajm -> AJ, uaq -> UQ, rak -> RK, fuj -> FU), from Shopify's
 * own address data for AE (github.com/Shopify/worldwide data/regions/AE.yml).
 * @param {string} emirate
 * @returns {string|null}
 */
export function provinceCode(emirate) {
  return Object.hasOwn(EMIRATES, emirate) ? EMIRATES[emirate].province : null;
}

export const DELIVERY = Object.freeze({
  hub: { lat: 25.18, lng: 55.36 }, // Ras Al Khor hub
  expressKm: 20,
  expressOpen: 8,
  expressClose: 22,
  etaBase: 20,
  defaultCut: 18,
  cut: { dubai: 18, auh: 18, shj: 18, ajm: 18, uaq: 18, rak: 18, fuj: 18 },
  sameDayHours: 6,
  todayText: 'Today within 6 hours',
  tomorrowShort: 'Tomorrow by 11 AM',
  tomorrowText: 'Tomorrow morning before 11 AM',
  expressTag: '1hr-delivery',
  nearKm: 3,
  maxAreaKm: 60,
  uaeOffsetMinutes: 240,
});

/** The website's delivery areas, in its order. */
export const AREAS = Object.freeze([
  { name: 'Dubai Marina', emirate: 'dubai', lat: 25.08, lng: 55.14 },
  { name: 'Downtown Dubai', emirate: 'dubai', lat: 25.2, lng: 55.27 },
  { name: 'Business Bay', emirate: 'dubai', lat: 25.185, lng: 55.265 },
  { name: 'Jumeirah', emirate: 'dubai', lat: 25.21, lng: 55.24 },
  { name: 'Al Barsha', emirate: 'dubai', lat: 25.11, lng: 55.2 },
  { name: 'Deira', emirate: 'dubai', lat: 25.27, lng: 55.32 },
  { name: 'Mirdif', emirate: 'dubai', lat: 25.22, lng: 55.42 },
  { name: 'Dubai Silicon Oasis', emirate: 'dubai', lat: 25.12, lng: 55.38 },
  { name: 'Jebel Ali', emirate: 'dubai', lat: 25.01, lng: 55.03 },
  { name: 'Al Nahyan', emirate: 'auh', lat: 24.47, lng: 54.38 },
  { name: 'Al Reem Island', emirate: 'auh', lat: 24.5, lng: 54.4 },
  { name: 'Khalifa City', emirate: 'auh', lat: 24.42, lng: 54.57 },
  { name: 'Yas Island', emirate: 'auh', lat: 24.49, lng: 54.6 },
  { name: 'Al Jimi (Al Ain)', emirate: 'auh', lat: 24.24, lng: 55.74 },
  { name: 'Al Majaz', emirate: 'shj', lat: 25.33, lng: 55.385 },
  { name: 'Muwaileh', emirate: 'shj', lat: 25.3, lng: 55.45 },
  { name: 'Al Nuaimiya', emirate: 'ajm', lat: 25.39, lng: 55.45 },
  { name: 'Al Salamah', emirate: 'uaq', lat: 25.56, lng: 55.55 },
  { name: 'Al Nakheel', emirate: 'rak', lat: 25.79, lng: 55.95 },
  { name: 'Al Faseel', emirate: 'fuj', lat: 25.12, lng: 56.33 },
]);

/**
 * UAE wall-clock time of `now` in fractional hours (0 <= h < 24), whole
 * minutes only, like the app.
 * @param {Date} now
 */
export function uaeHours(now) {
  const minutes = now.getUTCHours() * 60 + now.getUTCMinutes() + DELIVERY.uaeOffsetMinutes;
  return (minutes % 1440) / 60;
}

/** 12-hour label: "8 AM", "6 PM", "4:15 PM", "12 AM". */
export function formatHour(h) {
  const m = ((Math.round(h * 60) % 1440) + 1440) % 1440;
  const hour = Math.trunc(m / 60);
  const minute = m % 60;
  const ap = hour < 12 ? 'AM' : 'PM';
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  const mm = minute === 0 ? '' : `:${String(minute).padStart(2, '0')}`;
  return `${h12}${mm} ${ap}`;
}

/** Time left: "3h 20m", "10h 0m", "45m". */
export function formatLeft(h) {
  const m = Math.max(0, Math.round(h * 60));
  return `${m >= 60 ? `${Math.trunc(m / 60)}h ` : ''}${m % 60}m`;
}

/** Great-circle distance in km (haversine, R = 6371); `b` defaults to the hub. */
export function km(a, b = DELIVERY.hub) {
  const r = (x) => (x * Math.PI) / 180;
  const dLat = r(a.lat - b.lat);
  const dLng = r(a.lng - b.lng);
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(s));
}

export function cutHour(emirate) {
  return DELIVERY.cut[emirate] ?? DELIVERY.defaultCut;
}

/**
 * The Fresh Market promise for any place in `emirate` at `now`.
 * @param {string} emirate
 * @param {Date} now
 */
export function marketPromise(emirate, now) {
  const cut = cutHour(emirate);
  const h = uaeHours(now);
  const hrs = DELIVERY.sameDayHours;
  if (h < cut) {
    const by = formatHour(Math.ceil((h + hrs) * 4) / 4);
    return {
      today: true,
      line: DELIVERY.todayText,
      slot: `Today by ${by}`,
      short: `Within ${hrs} hrs`,
      by,
      left: formatLeft(cut - h),
      cutHour: cut,
    };
  }
  return {
    today: false,
    line: DELIVERY.tomorrowText,
    slot: DELIVERY.tomorrowShort,
    short: DELIVERY.tomorrowShort,
    by: null,
    left: null,
    cutHour: cut,
  };
}

export function isExpressOpen(now) {
  const h = uaeHours(now);
  return h >= DELIVERY.expressOpen && h < DELIVERY.expressClose;
}

/**
 * The Express promise for a point at `now`.
 * @param {{lat: number, lng: number}} point
 * @param {Date} now
 */
export function expressPromise(point, now) {
  const d = km(point);
  const eta = Math.max(15, Math.round((DELIVERY.etaBase + d * 1.5) / 5) * 5);
  return {
    covered: d <= DELIVERY.expressKm,
    open: isExpressOpen(now),
    etaMinutes: eta,
    range: `${eta - 5}–${eta + 5} min`, // en dash, like the app
    km: d,
  };
}

/** The nearest of the website's areas to a point, with its distance. */
export function nearestArea(lat, lng) {
  let best = AREAS[0];
  let bestKm = Infinity;
  for (const a of AREAS) {
    const d = km({ lat, lng }, a);
    if (d < bestKm) {
      bestKm = d;
      best = a;
    }
  }
  return { area: best, km: bestKm };
}

/** The app only delivers to points within 60 km of one of its areas. */
export function isDeliverablePoint(lat, lng) {
  return nearestArea(lat, lng).km <= DELIVERY.maxAreaKm;
}

/** "Dubai Marina, Dubai", or just the name when it already names the emirate. */
export function placeLabel(name, emirate) {
  const label = EMIRATES[emirate]?.label;
  if (!label) return name;
  return name.toLowerCase().includes(label.toLowerCase()) ? name : `${name}, ${label}`;
}

/** Exactly the products tagged "1hr-delivery" (any case) are on Express. */
export function isExpressTagged(tags) {
  return Array.isArray(tags) && tags.some((t) => typeof t === 'string' && t.trim().toLowerCase() === DELIVERY.expressTag);
}

export const MODE_LABEL = Object.freeze({ market: 'Fresh Market', express: 'Express' });
export const SHIPPING_TITLE = Object.freeze({ market: 'Fresh Market delivery', express: 'Express delivery' });

/**
 * What the server promises for this delivery, plus the reason Express
 * cannot be used here (null when it can).
 *
 * Fresh Market: the website's cart attribute text ("Today within 6 hours" /
 * "Tomorrow morning before 11 AM"). Express while open: the ETA range the
 * website sends ("25–35 min"). Express while closed (before 8 AM or from
 * 10 PM, which the app still lets the shopper choose): "Today from 8 AM" or
 * "Tomorrow from 8 AM", so the order never promises minutes it cannot keep.
 *
 * @param {'market'|'express'} mode
 * @param {{name: string, emirate: string, lat: number, lng: number}} area
 * @param {Date} now
 */
export function deliveryPromise(mode, area, now) {
  const mk = marketPromise(area.emirate, now);
  if (mode === 'market') return { promise: mk.line, expressProblem: null };
  const ex = expressPromise(area, now);
  if (!ex.covered) {
    return {
      promise: mk.line,
      expressProblem: `Express isn't available in ${area.name} yet. Fresh Market delivers ${mk.line.toLowerCase()}.`,
    };
  }
  if (ex.open) return { promise: ex.range, expressProblem: null };
  const day = uaeHours(now) < DELIVERY.expressOpen ? 'Today' : 'Tomorrow';
  return { promise: `${day} from ${formatHour(DELIVERY.expressOpen)}`, expressProblem: null };
}

/** "25.08000,55.14000", the website's "Delivery pin" format. */
export function pinOf(lat, lng) {
  return `${lat.toFixed(5)},${lng.toFixed(5)}`;
}
