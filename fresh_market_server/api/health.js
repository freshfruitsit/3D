// GET /api/health -> {ok: true, version}
import { createHealthHandler } from '../lib/handlers.js';

export default { fetch: createHealthHandler() };
