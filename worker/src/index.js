// Prebake Cloudflare Worker
//
// GET    /gems/{cache_key}         - fetch prebake gem from R2 (public)
// PUT    /gems/{cache_key}         - upload prebake gem to R2 (authenticated)
// HEAD   /gems/{cache_key}         - check existence in R2 (public)
// DELETE /gems/{cache_key}         - delete gem from R2 (authenticated)
// GET    /gems/{cache_key}.sha256  - fetch checksum (public)
// PUT    /gems/{cache_key}.sha256  - upload checksum (authenticated)
// DELETE /gems/{cache_key}.sha256  - delete checksum (authenticated)

import { CACHE_KEY_REGEX, parseCacheKey } from "./build-trigger.js";
import {
  handleGet,
  handleHead,
  handlePut,
  handleDelete,
  handleGetChecksum,
  handlePutChecksum,
} from "./handlers.js";

const SUPPORTED_PLATFORMS = new Set(["x86_64-linux", "aarch64-linux"]);
const CHECKSUM_SUFFIX = ".sha256";

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    const match = path.match(/^\/gems\/(.+)$/);
    if (!match) {
      return new Response("Not found", { status: 404 });
    }

    const rawKey = match[1];

    const isChecksum = rawKey.endsWith(CHECKSUM_SUFFIX);
    const cacheKey = isChecksum
      ? rawKey.slice(0, -CHECKSUM_SUFFIX.length)
      : rawKey;

    // Validate cache key format before dispatching to any handler.
    // Prevents access to internal R2 objects (e.g., _pending/ markers).
    if (!CACHE_KEY_REGEX.test(cacheKey)) {
      return new Response("Not found", { status: 404 });
    }

    // Reject unsupported platforms early to avoid consuming rate-limit
    // quota, R2 reads, and GitHub Actions builds.
    const parsed = parseCacheKey(cacheKey);
    if (!parsed || !SUPPORTED_PLATFORMS.has(parsed.platform)) {
      return new Response("Not found", { status: 404 });
    }

    const clientIp = request.headers.get("cf-connecting-ip") || "unknown";
    const { success } = await env.RATE_LIMITER.limit({ key: clientIp });
    if (!success) {
      return new Response("Rate limit exceeded", { status: 429 });
    }

    if (isChecksum) {
      switch (request.method) {
        case "GET":
          return handleGetChecksum(rawKey, env);
        case "PUT":
          return handlePutChecksum(request, rawKey, env);
        case "DELETE":
          return handleDelete(request, rawKey, env);
        default:
          return new Response("Method not allowed", { status: 405 });
      }
    }

    switch (request.method) {
      case "GET":
        return handleGet(cacheKey, env, ctx, clientIp);
      case "HEAD":
        return handleHead(cacheKey, env);
      case "PUT":
        return handlePut(request, cacheKey, env);
      case "DELETE":
        return handleDelete(request, cacheKey, env);
      default:
        return new Response("Method not allowed", { status: 405 });
    }
  },
};
