import { triggerBuild } from "./build-trigger.js";
import { requireAuth, timingSafeEqual } from "./utils.js";

const MAX_UPLOAD_SIZE = 50 * 1024 * 1024; // 50MB
const MAX_CHECKSUM_SIZE = 128; // generous upper bound; SHA-256 hex is 64 chars

export async function handleGet(cacheKey, env, ctx, clientIp) {
  const object = await env.R2_BUCKET.get(cacheKey);

  if (!object) {
    ctx.waitUntil(
      triggerBuild(cacheKey, env, clientIp).catch((err) =>
        console.error(`Failed to trigger build for ${cacheKey}:`, err),
      ),
    );

    return new Response("Not found", { status: 404 });
  }

  const headers = new Headers();
  headers.set("Content-Type", "application/octet-stream");
  headers.set("Content-Length", object.size);
  headers.set("Cache-Control", "public, max-age=31536000, immutable");
  headers.set("ETag", object.httpEtag);

  return new Response(object.body, { headers });
}

export async function handleHead(cacheKey, env) {
  const object = await env.R2_BUCKET.head(cacheKey);

  if (!object) {
    return new Response(null, { status: 404 });
  }

  const headers = new Headers();
  headers.set("Content-Length", object.size);
  headers.set("Cache-Control", "public, max-age=31536000, immutable");

  return new Response(null, { status: 200, headers });
}

export async function handlePut(request, cacheKey, env) {
  const denied = await requireAuth(request, env);
  if (denied) return denied;

  const buildNonce = request.headers.get("X-Build-Nonce");
  if (!buildNonce) {
    return new Response("Missing build nonce", { status: 403 });
  }

  const pendingKey = `_pending/${cacheKey}`;
  const [pending, existing] = await Promise.all([
    env.R2_BUCKET.get(pendingKey),
    env.R2_BUCKET.head(cacheKey),
  ]);

  if (!pending) {
    return new Response("No pending build for this key", { status: 403 });
  }
  const metadata = pending.customMetadata;
  if (!metadata || !metadata.nonce) {
    return new Response("Invalid build nonce", { status: 403 });
  }
  if (!(await timingSafeEqual(metadata.nonce, buildNonce))) {
    return new Response("Invalid build nonce", { status: 403 });
  }

  if (existing) {
    await env.R2_BUCKET.delete(pendingKey);
    return new Response("Already exists", { status: 409 });
  }

  const contentLength = parseInt(
    request.headers.get("Content-Length") || "0",
    10,
  );
  if (contentLength > MAX_UPLOAD_SIZE) {
    return new Response(
      `File too large: ${contentLength} > ${MAX_UPLOAD_SIZE}`,
      { status: 413 },
    );
  }

  await env.R2_BUCKET.put(cacheKey, request.body, {
    httpMetadata: {
      contentType: "application/octet-stream",
    },
  });

  await env.R2_BUCKET.delete(pendingKey);

  return new Response("OK", { status: 201 });
}

export async function handleDelete(request, cacheKey, env) {
  const denied = await requireAuth(request, env);
  if (denied) return denied;

  await env.R2_BUCKET.delete(cacheKey);
  return new Response("OK", { status: 200 });
}

export async function handleGetChecksum(checksumKey, env) {
  const object = await env.R2_BUCKET.get(checksumKey);

  if (!object) {
    return new Response("Not found", { status: 404 });
  }

  return new Response(object.body, {
    headers: {
      "Content-Type": "text/plain",
      "Cache-Control": "public, max-age=31536000, immutable",
    },
  });
}

export async function handlePutChecksum(request, checksumKey, env) {
  const denied = await requireAuth(request, env);
  if (denied) return denied;

  const body = await request.text();
  if (body.length > MAX_CHECKSUM_SIZE) {
    return new Response("Checksum too large", { status: 413 });
  }

  await env.R2_BUCKET.put(checksumKey, body, {
    httpMetadata: { contentType: "text/plain" },
  });

  return new Response("OK", { status: 201 });
}
