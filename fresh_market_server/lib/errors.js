// Errors that carry the HTTP answer the app gets. Every response body is JSON
// with at least { error, message }.

export class ApiError extends Error {
  /**
   * @param {number} status HTTP status for the app
   * @param {string} code short machine code ("invalid", "unauthorized", ...)
   * @param {string} message human text, safe to show
   * @param {Record<string, unknown>} [extra] more JSON fields for the body
   * @param {Record<string, string>} [headers] extra response headers
   * @param {string} [logDetail] written to the log only, never sent to the app
   */
  constructor(status, code, message, extra = {}, headers = {}, logDetail = '') {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
    this.extra = extra;
    this.headers = headers;
    this.logDetail = logDetail;
  }

  toBody() {
    return { error: this.code, message: this.message, ...this.extra };
  }
}

/**
 * 422 with the contract's {field, message}, plus every error in `errors`.
 * @param {{field: string, message: string}[]} errors
 */
export function validationError(errors) {
  const [first] = errors;
  return new ApiError(422, 'invalid', first.message, { field: first.field, errors });
}

/** 401: the customer must sign in again. */
export function unauthorized(message = 'Please sign in again.') {
  return new ApiError(401, 'unauthorized', message, {}, { 'WWW-Authenticate': 'Bearer' });
}

/**
 * 429 from this server's own per-customer limit, or a customer-level
 * Shopify limit.
 * @param {number} retryAfterSeconds
 * @param {string} message
 */
export function rateLimited(retryAfterSeconds, message) {
  const seconds = Math.max(1, Math.ceil(retryAfterSeconds));
  return new ApiError(429, 'rate_limited', message, { retryAfterSeconds: seconds }, {
    'Retry-After': String(seconds),
  });
}

/**
 * A Shopify call failed in a way the app may retry with the same
 * Idempotency-Key (network error, Shopify 5xx, Shopify throttling).
 */
export class UpstreamError extends Error {
  /**
   * @param {string} message internal message (logged, not sent)
   * @param {{retryable?: boolean, retryAfterSeconds?: number, kind?: string}} [opts]
   */
  constructor(message, { retryable = true, retryAfterSeconds, kind = 'upstream' } = {}) {
    super(message);
    this.name = 'UpstreamError';
    this.retryable = retryable;
    this.retryAfterSeconds = retryAfterSeconds;
    this.kind = kind;
  }
}

/** The server itself is set up wrongly (missing env, scopes, store settings). */
export class ConfigError extends Error {
  /** @param {string} message internal message (logged, not sent) */
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}

/**
 * Turns any thrown value into the response the app gets.
 * @param {unknown} err
 * @returns {ApiError}
 */
export function toApiError(err) {
  if (err instanceof ApiError) return err;
  if (err instanceof UpstreamError) {
    const headers = err.retryAfterSeconds ? { 'Retry-After': String(Math.ceil(err.retryAfterSeconds)) } : {};
    if (err.kind === 'in_progress') {
      return new ApiError(503, 'in_progress', 'Your order is still being placed. Please wait a moment.', { retryable: true }, headers);
    }
    return new ApiError(
      503,
      err.kind === 'throttled' ? 'busy' : 'unavailable',
      err.retryable
        ? 'The shop is busy right now. Please try again in a moment.'
        : 'The shop cannot take orders right now.',
      { retryable: err.retryable },
      headers,
    );
  }
  if (err instanceof ConfigError) {
    return new ApiError(500, 'server_misconfigured', 'The shop cannot take orders right now.', {
      retryable: false,
    });
  }
  return new ApiError(500, 'internal', 'Something went wrong. Please try again.', { retryable: true });
}

/**
 * Shopify's text for the log with customer values taken out: anything it
 * quoted ("..."), email addresses and international phone numbers. Shopify's
 * input-error messages can repeat the values that were sent.
 * @param {unknown} text
 */
export function scrub(text) {
  return scrubContacts(String(text ?? '').replace(/"[^"]*"/g, '"…"'));
}

/** Email addresses and international phone numbers out, everything else kept. */
export function scrubContacts(text) {
  return String(text ?? '')
    .replace(/[^\s"'<>@(),;:]+@[^\s"'<>@(),;:]+\.[a-z]{2,}/gi, '[email]')
    .replace(/\+\d[\d ]{6,}\d/g, '[phone]');
}
