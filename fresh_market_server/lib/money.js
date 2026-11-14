// Money is held as integer fils (1 AED = 100 fils) everywhere in this server.
//
// Shopify's Admin API returns money as a decimal string without a currency
// symbol ("A monetary value string without a currency symbol or code.
// Example value: "100.57"",
// https://shopify.dev/docs/api/admin-graphql/2026-10/scalars/Money), and
// MoneyBag.shopMoney.amount is a Decimal string. These helpers parse those
// strings digit by digit, never through floating point.

const DECIMAL = /^(-)?(\d+)(?:\.(\d+))?$/;

/**
 * "19.95" -> 1995, "20" -> 2000, "20.5" -> 2050, "0.125" -> 13 (half up).
 * Returns null for anything that is not a plain decimal number.
 * @param {unknown} value
 * @returns {number|null}
 */
export function decimalToFils(value) {
  let text;
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) return null;
    text = value.toFixed(6);
  } else if (typeof value === 'string') {
    text = value.trim();
  } else {
    return null;
  }
  const m = DECIMAL.exec(text);
  if (!m) return null;
  const [, minus, whole, frac = ''] = m;
  const two = (frac + '00').slice(0, 2);
  let fils = Number(whole) * 100 + Number(two);
  const rest = frac.slice(2);
  if (rest.length > 0 && rest[0] >= '5') fils += 1; // half up on the third digit
  if (!Number.isSafeInteger(fils)) return null;
  return minus && fils !== 0 ? -fils : fils;
}

/**
 * 2500 -> "25.00" (the shape Shopify's MoneyInput.amount takes).
 * @param {number} fils
 */
export function filsToDecimal(fils) {
  if (!Number.isSafeInteger(fils)) throw new TypeError(`fils must be an integer, got ${fils}`);
  const sign = fils < 0 ? '-' : '';
  const abs = Math.abs(fils);
  return `${sign}${Math.trunc(abs / 100)}.${String(abs % 100).padStart(2, '0')}`;
}

/**
 * 1995 -> "AED 19.95", for messages the app shows as they are.
 * @param {number} fils
 */
export function formatAed(fils) {
  const sign = fils < 0 ? '-' : '';
  const abs = Math.abs(fils);
  const whole = String(Math.trunc(abs / 100)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${sign}AED ${whole}.${String(abs % 100).padStart(2, '0')}`;
}
