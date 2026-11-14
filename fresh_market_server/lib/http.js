// Small helpers shared by the api/ functions: JSON responses, body reading,
// one error format, and a log line per request that never carries secrets
// or personal data.

import { randomUUID } from 'node:crypto';
import { ApiError, toApiError, UpstreamError, ConfigError, scrubContacts } from './errors.js';

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

const tooLarge = () => new ApiError(413, 'too_large', 'The request is too large.', { field: 'body' });

/**
 * Reads a JSON body of at most MAX_BODY_BYTES. The body is read chunk by
 * chunk and reading stops as soon as the limit is passed, also when no
 * Content-Length was sent (chunked upload).
 * @param {Request} request
 */
export async function readJson(request) {
  const type = request.headers.get('content-type') ?? '';
  if (!/^application\/json\b/i.test(type)) {
    throw new ApiError(415, 'unsupported_media_type', 'Send the body as application/json.', { field: 'body' });
  }
  const declared = Number(request.headers.get('content-length') ?? '0');
  if (declared > MAX_BODY_BYTES) throw tooLarge();
  const raw = await readCapped(request, MAX_BODY_BYTES);
  try {
    return JSON.parse(raw);
  } catch {
    throw new ApiError(400, 'bad_json', 'The body is not valid JSON.', { field: 'body' });
  }
}

/** @param {Request} request @param {number} max */
async function readCapped(request, max) {
  if (!request.body) return '';
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > max) {
      reader.cancel().catch(() => {});
      throw tooLarge();
    }
    chunks.push(value);
  }
  return new TextDecoder('utf-8').decode(Buffer.concat(chunks));
}

/**
 * One structured log line. Callers pass only ids, counts, codes and
 * timings: no tokens, names, emails, phones or addresses. A line with an
 * `alert` (something staff must look at) is written at error level.
 * @param {Record<string, unknown>} fields
 */
export function log(fields) {
  const line = JSON.stringify({ t: new Date().toISOString(), ...fields });
  if (fields.alert) console.error(line);
  else console.log(line);
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
          // Internal messages hold no secrets. Shopify's text inside them is
          // already scrubbed (firstMessage); contact details are taken out
          // once more here in case any slipped through.
          logFields.detail = scrubContacts(err instanceof Error ? err.message : String(err)).slice(0, 500);
        } else if (err.logDetail) {
          logFields.detail = scrubContacts(err.logDetail).slice(0, 500);
        }
        response = json(apiError.status, { ...apiError.toBody(), requestId }, apiError.headers);
      }
    }
    response.headers.set('X-Request-Id', requestId);
    write({ route, method: request.method, status: response.status, ms: Date.now() - started, requestId, ...logFields });
    return response;
  };
}
