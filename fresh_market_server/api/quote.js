// POST /api/quote: prices, stock, delivery fee and promise from Shopify.
import { createQuoteHandler } from '../lib/handlers.js';

export default { fetch: createQuoteHandler() };
