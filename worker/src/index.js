// Prebake Cloudflare Worker
//
// GET  /gems/{cache_key} - fetch prebake gem from R2 (public)
// PUT  /gems/{cache_key} - upload prebake gem to R2 (authenticated)
// HEAD /gems/{cache_key} - check existence in R2 (public)

import { CACHE_KEY_REGEX } from "./build-trigger.js";
import { handleGet, handleHead, handlePut } from "./handlers.js";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    const match = path.match(/^\/gems\/(.+)$/);
    if (!match) {
      return new Response("Not found", { status: 404 });
    }

    const cacheKey = match[1];

    // Validate cache key format before dispatching to any handler.
    // Prevents access to internal R2 objects (e.g., _pending/ markers).
    if (!CACHE_KEY_REGEX.test(cacheKey)) {
      return new Response("Not found", { status: 404 });
    }

    const clientIp = request.headers.get("cf-connecting-ip") || "unknown";
    const { success } = await env.RATE_LIMITER.limit({ key: clientIp });
    if (!success) {
      return new Response("Rate limit exceeded", { status: 429 });
    }

    switch (request.method) {
      case "GET":
        return handleGet(cacheKey, env, ctx, clientIp);
      case "HEAD":
        return handleHead(cacheKey, env);
      case "PUT":
        return handlePut(request, cacheKey, env);
      default:
        return new Response("Method not allowed", { status: 405 });
    }
  },
};
