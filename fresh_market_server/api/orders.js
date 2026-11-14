// POST /api/orders: creates the cash-on-delivery order in Shopify.
import { createOrdersHandler } from '../lib/handlers.js';

export default { fetch: createOrdersHandler() };
