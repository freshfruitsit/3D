// Small helpers shared by the api/ functions: JSON responses, body reading,
// one error format, and a log line per request that never carries secrets
// or personal data.

import { randomUUID } from 'node:crypto';
import { ApiError, toApiError, UpstreamError, ConfigError } from './errors.js';

export const MAX_BODY_BYTES = 64 * 1024;

/**
 * @param {number} status
 * @param {unknown} body
 * @param {Record<string, string>} [headers]
 */
export function json(status, body, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      ...headers,
    },
  });
}

/**
 * Reads a JSON body of at most MAX_BODY_BYTES.
 * @param {Request} request
 */
export async function readJson(request) {
  const type = request.headers.get('content-type') ?? '';
  if (!/^application\/json\b/i.test(type)) {
    throw new ApiError(415, 'unsupported_media_type', 'Send the body as application/json.', { field: 'body' });
  }
  const declared = Number(request.headers.get('content-length') ?? '0');
  if (declared > MAX_BODY_BYTES) {
    throw new ApiError(413, 'too_large', 'The request is too large.', { field: 'body' });
  }
  const raw = await request.text();
  if (Buffer.byteLength(raw, 'utf8') > MAX_BODY_BYTES) {
    throw new ApiError(413, 'too_large', 'The request is too large.', { field: 'body' });
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new ApiError(400, 'bad_json', 'The body is not valid JSON.', { field: 'body' });
  }
}

/**
 * One structured log line. Callers pass only ids, counts, codes and
 * timings: no tokens, names, emails, phones or addresses.
 * @param {Record<string, unknown>} fields
 */
export function log(fields) {
  console.log(JSON.stringify({ t: new Date().toISOString(), ...fields }));
}

/**
 * Wraps a route: method check, request id, error mapping, one log line.
 * @param {string} route
 * @param {string[]} methods
 * @param {(request: Request, meta: {requestId: string, logFields: Record<string, unknown>}) => Promise<Response>} handler
 * @param {{log?: typeof log}} [opts]
 */
export function route(route, methods, handler, { log: write = log } = {}) {
  return async (request) => {
    const requestId = randomUUID();
    const started = Date.now();
    const logFields = {};
    let response;
    if (!methods.includes(request.method)) {
      response = json(405, { error: 'method_not_allowed', message: `Use ${methods.join(' or ')}.` }, { Allow: methods.join(', ') });
    } else {
      try {
        response = await handler(request, { requestId, logFields });
      } catch (err) {
        const apiError = toApiError(err);
        if (!(err instanceof ApiError)) {
          logFields.failure = err instanceof UpstreamError || err instanceof ConfigError ? err.name : 'Unexpected';
          // Internal messages are written by this server and hold no secrets.
          logFields.detail = err instanceof Error ? err.message.slice(0, 500) : String(err).slice(0, 200);
        }
        response = json(apiError.status, { ...apiError.toBody(), requestId }, apiError.headers);
      }
    }
    response.headers.set('X-Request-Id', requestId);
    write({ route, method: request.method, status: response.status, ms: Date.now() - started, requestId, ...logFields });
    return response;
  };
}
