// Checks and cleans what the app sends. Every problem becomes a
// {field, message} pair; the handler answers 422 with all of them.

import { EMIRATES, isDeliverablePoint, km, pinOf } from './delivery.js';

/** Field limits, matching the app's CustomerInput (customer_details.dart). */
export const LIMITS = Object.freeze({
  name: 60,
  address1: 170, // building (80) + ", " + street (80), with room to spare
  address2: 60, // flat (40)
  city: 80,
  areaName: 80,
  instructions: 200,
  note: 500,
  promise: 120,
  token: 8192,
});

/** One line of typed text: control characters and runs of spaces become one space. */
export function cleanLine(input) {
  return String(input)
    .replace(/[\u0000-\u001F\u007F]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** A note keeps its line breaks but loses other control characters. */
export function cleanNote(input) {
  return String(input)
    .replace(/\r\n?/g, '\n')
    .replace(/[\u0000-\u0009\u000B-\u001F\u007F]/g, ' ')
    .split('\n')
    .map((l) => l.replace(/\s+/g, ' ').trim())
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function asciiDigits(input) {
  let out = '';
  for (const ch of input) {
    const c = ch.codePointAt(0);
    if (c >= 0x0660 && c <= 0x0669) out += String.fromCharCode(0x30 + c - 0x0660);
    else if (c >= 0x06f0 && c <= 0x06f9) out += String.fromCharCode(0x30 + c - 0x06f0);
    else out += ch;
  }
  return out;
}

/**
 * The app's CustomerInput.normaliseMobile: UAE mobiles in any common form
 * become +9715XXXXXXXX; other international numbers written with + or 00
 * become + and their 8 to 15 digits (E.164, which Shopify's
 * MailingAddressInput.phone asks for). Returns null when unusable.
 * @param {string} input
 */
export function normaliseMobile(input) {
  let s = asciiDigits(String(input).trim());
  if (!s) return null;
  s = s.replace(/[\s\-.() ‎‏‪-‮]/g, '');
  if (s.startsWith('00')) s = `+${s.slice(2)}`;
  const plus = s.startsWith('+');
  const digits = plus ? s.slice(1) : s;
  if (!digits || !/^\d+$/.test(digits)) return null;
  const uae = (national) => (/^5\d{8}$/.test(national) ? `+971${national}` : null);
  if (plus) {
    if (digits.startsWith('971')) {
      let rest = digits.slice(3);
      if (rest.startsWith('0')) rest = rest.slice(1);
      return uae(rest);
    }
    if (digits.startsWith('0') || digits.length < 8 || digits.length > 15) return null;
    return `+${digits}`;
  }
  if (digits.length === 12 && digits.startsWith('971')) return uae(digits.slice(3));
  if (digits.length === 10 && digits.startsWith('05')) return uae(digits.slice(1));
  if (digits.length === 9) return uae(digits);
  return null;
}

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * Normalises a variant ID from the app: 44123, "44123" or
 * "gid://shopify/ProductVariant/44123".
 * @returns {{gid: string, numeric: string}|null}
 */
export function parseVariantId(value) {
  let digits = null;
  if (typeof value === 'number' && Number.isSafeInteger(value) && value > 0) digits = String(value);
  else if (typeof value === 'string') {
    const m = /^(?:gid:\/\/shopify\/ProductVariant\/)?([1-9]\d{0,19})$/.exec(value.trim());
    if (m) digits = m[1];
  }
  return digits ? { gid: `gid://shopify/ProductVariant/${digits}`, numeric: digits } : null;
}

/**
 * @param {unknown} lines
 * @param {{maxLines: number, maxQtyPerLine: number}} limits
 * @param {{field: string, message: string}[]} errors
 */
export function parseLines(lines, limits, errors) {
  if (!Array.isArray(lines) || lines.length === 0) {
    errors.push({ field: 'lines', message: 'Your basket is empty.' });
    return [];
  }
  if (lines.length > limits.maxLines) {
    errors.push({ field: 'lines', message: `An order can have at most ${limits.maxLines} different items.` });
    return [];
  }
  const out = [];
  const seen = new Set();
  lines.forEach((line, i) => {
    const at = `lines[${i}]`;
    if (!isObject(line)) {
      errors.push({ field: at, message: 'Each line needs a variantId and a quantity.' });
      return;
    }
    const id = parseVariantId(line.variantId);
    if (!id) {
      errors.push({ field: `${at}.variantId`, message: 'Unknown item.' });
      return;
    }
    if (seen.has(id.numeric)) {
      errors.push({ field: `${at}.variantId`, message: 'The same item is in the basket twice.' });
      return;
    }
    seen.add(id.numeric);
    const q = line.quantity;
    if (!Number.isInteger(q) || q < 1) {
      errors.push({ field: `${at}.quantity`, message: 'Quantity must be a whole number of at least 1.' });
      return;
    }
    if (q > limits.maxQtyPerLine) {
      errors.push({ field: `${at}.quantity`, message: `You can order at most ${limits.maxQtyPerLine} of one item.` });
      return;
    }
    let unitPriceFils;
    if (line.unitPriceFils !== undefined && line.unitPriceFils !== null) {
      if (!Number.isSafeInteger(line.unitPriceFils) || line.unitPriceFils < 0) {
        errors.push({ field: `${at}.unitPriceFils`, message: 'unitPriceFils must be a whole number of fils.' });
        return;
      }
      unitPriceFils = line.unitPriceFils;
    }
    out.push({ variantId: line.variantId, gid: id.gid, numeric: id.numeric, quantity: q, unitPriceFils });
  });
  return out;
}

function text(obj, key, field, max, errors, { required = true, clean = cleanLine } = {}) {
  const v = obj?.[key];
  if (v === undefined || v === null || v === '') {
    if (required) errors.push({ field, message: 'This is required.' });
    return '';
  }
  if (typeof v !== 'string') {
    errors.push({ field, message: 'This must be text.' });
    return '';
  }
  const s = clean(v);
  if (!s && required) {
    errors.push({ field, message: 'This is required.' });
    return '';
  }
  if (s.length > max) {
    errors.push({ field, message: `At most ${max} characters.` });
    return '';
  }
  return s;
}

// The UAE with a margin; anything outside is a broken pin.
const inUae = (lat, lng) => lat >= 22 && lat <= 27 && lng >= 51 && lng <= 57;

/**
 * In the app, delivery.area's lat/lng already is the shopper's pin
 * (delivery_rules.dart: DeliveryPlace.at "the website keeps the pin"), and
 * every rule (Express zone, 60 km reach) is checked on it. A `pin` further
 * than this from the area would send the driver somewhere the rules never
 * looked at, so it is refused.
 */
export const PIN_MATCH_KM = 0.2;

/**
 * @param {unknown} delivery
 * @param {{field: string, message: string}[]} errors
 * @param {{forOrder?: boolean}} [opts]
 * @returns {{mode: 'market'|'express', area: {name: string, emirate: string, lat: number, lng: number}, pin: string, promise: string}|null}
 */
export function parseDelivery(delivery, errors, { forOrder = false } = {}) {
  if (!isObject(delivery)) {
    errors.push({ field: 'delivery', message: 'Choose where to deliver.' });
    return null;
  }
  const before = errors.length;
  const mode = delivery.mode;
  if (mode !== 'express' && mode !== 'market') {
    errors.push({ field: 'delivery.mode', message: "Delivery mode must be 'express' or 'market'." });
  }
  const area = delivery.area;
  let parsedArea = null;
  if (!isObject(area)) {
    errors.push({ field: 'delivery.area', message: 'Choose where to deliver.' });
  } else {
    const name = text(area, 'name', 'delivery.area.name', LIMITS.areaName, errors);
    const emirate = area.emirate;
    if (typeof emirate !== 'string' || !Object.hasOwn(EMIRATES, emirate)) {
      errors.push({ field: 'delivery.area.emirate', message: 'Choose one of the seven emirates.' });
    }
    const { lat, lng } = area;
    const okPoint = typeof lat === 'number' && typeof lng === 'number' && Number.isFinite(lat) && Number.isFinite(lng);
    if (!okPoint || !inUae(lat, lng)) {
      errors.push({ field: 'delivery.area', message: 'The delivery location is not in the UAE.' });
    } else if (!isDeliverablePoint(lat, lng)) {
      errors.push({ field: 'delivery.area', message: "We don't deliver here yet. We deliver across the seven emirates of the UAE." });
    }
    if (errors.length === before) parsedArea = { name, emirate, lat, lng };
  }
  if (delivery.pin !== undefined && delivery.pin !== null && delivery.pin !== '') {
    const m = typeof delivery.pin === 'string' ? /^\s*(-?\d{1,3}(?:\.\d{1,10})?)\s*,\s*(-?\d{1,3}(?:\.\d{1,10})?)\s*$/.exec(delivery.pin) : null;
    if (!m || !inUae(Number(m[1]), Number(m[2]))) {
      errors.push({ field: 'delivery.pin', message: "The pin must be 'lat,lng' inside the UAE." });
    } else if (parsedArea && km({ lat: Number(m[1]), lng: Number(m[2]) }, parsedArea) > PIN_MATCH_KM) {
      errors.push({ field: 'delivery.pin', message: "The map pin doesn't match the delivery area. Please choose the place again." });
    }
  }
  const promise = forOrder
    ? text(delivery, 'promise', 'delivery.promise', LIMITS.promise, errors, { required: false })
    : '';
  if (errors.length !== before || !parsedArea) return null;
  // The pin the driver gets is the point the rules were checked on.
  return { mode, area: parsedArea, pin: pinOf(parsedArea.lat, parsedArea.lng), promise };
}

/**
 * @param {unknown} address
 * @param {string|undefined} deliveryEmirate the emirate of delivery.area
 * @param {{field: string, message: string}[]} errors
 */
export function parseAddress(address, deliveryEmirate, errors) {
  if (!isObject(address)) {
    errors.push({ field: 'address', message: 'Add your delivery address.' });
    return null;
  }
  const before = errors.length;
  const firstName = text(address, 'firstName', 'address.firstName', LIMITS.name, errors);
  const lastName = text(address, 'lastName', 'address.lastName', LIMITS.name, errors);
  const address1 = text(address, 'address1', 'address.address1', LIMITS.address1, errors);
  const address2 = text(address, 'address2', 'address.address2', LIMITS.address2, errors, { required: false });
  const city = text(address, 'city', 'address.city', LIMITS.city, errors);
  const emirate = address.emirate;
  if (typeof emirate !== 'string' || !Object.hasOwn(EMIRATES, emirate)) {
    errors.push({ field: 'address.emirate', message: 'Choose one of the seven emirates.' });
  } else if (deliveryEmirate && emirate !== deliveryEmirate) {
    errors.push({ field: 'address.emirate', message: 'The address is in a different emirate from the delivery area.' });
  }
  let phone = null;
  if (typeof address.phone !== 'string' || !address.phone.trim()) {
    errors.push({ field: 'address.phone', message: 'Add a mobile number so the driver can call you.' });
  } else {
    phone = normaliseMobile(address.phone);
    if (!phone) errors.push({ field: 'address.phone', message: 'Enter a UAE mobile like 050 123 4567, or a number starting with +.' });
  }
  if (errors.length !== before) return null;
  return { firstName, lastName, address1, address2, city, emirate, phone };
}

/**
 * Body of POST /api/quote.
 * @param {unknown} body
 * @param {{maxLines: number, maxQtyPerLine: number}} limits
 */
export function parseQuoteBody(body, limits) {
  const errors = [];
  if (!isObject(body)) return { errors: [{ field: 'body', message: 'Send a JSON object.' }] };
  const lines = parseLines(body.lines, limits, errors);
  const delivery = parseDelivery(body.delivery, errors);
  return { errors, lines, delivery };
}

/**
 * Body of POST /api/orders.
 * @param {unknown} body
 * @param {{maxLines: number, maxQtyPerLine: number}} limits
 */
export function parseOrderBody(body, limits) {
  const errors = [];
  if (!isObject(body)) return { errors: [{ field: 'body', message: 'Send a JSON object.' }] };
  const lines = parseLines(body.lines, limits, errors);
  const delivery = parseDelivery(body.delivery, errors, { forOrder: true });
  const emirate = isObject(body.delivery) && isObject(body.delivery.area) ? body.delivery.area.emirate : undefined;
  const address = parseAddress(body.address, typeof emirate === 'string' ? emirate : undefined, errors);
  const instructions = text(body, 'instructions', 'instructions', LIMITS.instructions, errors, { required: false });
  const note = text(body, 'note', 'note', LIMITS.note, errors, { required: false, clean: cleanNote });
  let expectedTotalFils;
  if (body.expectedTotalFils !== undefined && body.expectedTotalFils !== null) {
    if (!Number.isSafeInteger(body.expectedTotalFils) || body.expectedTotalFils < 0) {
      errors.push({ field: 'expectedTotalFils', message: 'expectedTotalFils must be a whole number of fils.' });
    } else {
      expectedTotalFils = body.expectedTotalFils;
    }
  }
  return { errors, lines, delivery, address, instructions, note, expectedTotalFils };
}

/** The Idempotency-Key header: a UUID, lower-cased. */
export function parseIdempotencyKey(value) {
  const v = (value ?? '').trim().toLowerCase();
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(v) ? v : null;
}

/** "Bearer <token>" -> token, or null. */
export function parseBearer(value) {
  const m = /^Bearer\s+(\S+)\s*$/i.exec(value ?? '');
  if (!m || m[1].length > LIMITS.token) return null;
  return m[1];
}
