import test from "node:test";
import assert from "node:assert/strict";

import { triggerBuild } from "../src/build-trigger.js";

const CACHE_KEY = "io-console-0.9.3-aarch64-linux-ruby4.0.gem";
const PENDING_KEY = `_pending/${CACHE_KEY}`;

// Minimal R2 stand-in. put() honours onlyIf and, like R2, returns null when the
// condition fails. Its body has no await, so the check and the write land in one
// microtask, which is what makes it a faithful model of an atomic conditional put.
class FakeR2 {
  constructor() {
    this.objects = new Map();
    this.seq = 0;
  }

  async head(key) {
    const object = this.objects.get(key);
    return object ? { etag: object.etag, customMetadata: object.customMetadata } : null;
  }

  async get(key) {
    const object = this.objects.get(key);
    return object ? { ...object, text: async () => object.body } : null;
  }

  async put(key, body, options = {}) {
    const existing = this.objects.get(key);
    if (options.onlyIf && !conditionPasses(options.onlyIf, existing)) return null;

    const stored = {
      etag: `etag-${(this.seq += 1)}`,
      body,
      customMetadata: options.customMetadata,
    };
    this.objects.set(key, stored);
    return { etag: stored.etag };
  }

  async delete(key) {
    this.objects.delete(key);
  }
}

function conditionPasses(onlyIf, existing) {
  if (onlyIf instanceof Headers) {
    const ifNoneMatch = onlyIf.get("If-None-Match");
    if (ifNoneMatch === "*") return !existing;
    return true;
  }
  if (onlyIf.etagMatches) return Boolean(existing) && existing.etag === onlyIf.etagMatches;
  return true;
}

function setup({ pendingAgeMs } = {}) {
  const r2 = new FakeR2();
  const dispatches = [];

  if (pendingAgeMs !== undefined) {
    r2.objects.set(PENDING_KEY, {
      etag: "etag-stale",
      body: "",
      customMetadata: {
        triggered_at: new Date(Date.now() - pendingAgeMs).toISOString(),
        nonce: "pre-existing-nonce",
      },
    });
  }

  globalThis.fetch = async (url, init) => {
    if (String(url).includes("rubygems.org")) {
      return { ok: true, json: async () => [{ number: "0.9.3", platform: "ruby" }] };
    }
    dispatches.push(JSON.parse(init.body).inputs);
    return { ok: true };
  };

  const env = {
    R2_BUCKET: r2,
    BUILD_RATE_LIMITER: { limit: async () => ({ success: true }) },
    MAX_MONTHLY_BUILDS: "400",
    GITHUB_REPO: "gembakery/prebake",
    GITHUB_TOKEN: "token",
  };

  return { r2, env, dispatches };
}

test("concurrent cache misses dispatch exactly one build", async () => {
  const { r2, env, dispatches } = setup();

  await Promise.all([
    triggerBuild(CACHE_KEY, env, "1.2.3.4"),
    triggerBuild(CACHE_KEY, env, "1.2.3.4"),
    triggerBuild(CACHE_KEY, env, "1.2.3.4"),
  ]);

  assert.equal(dispatches.length, 1);

  // The surviving marker must authorise the build that was actually dispatched,
  // or that build 403s at push time.
  const marker = await r2.head(PENDING_KEY);
  assert.equal(marker.customMetadata.nonce, dispatches[0].build_nonce);
});

test("a pending marker under an hour old blocks re-dispatch", async () => {
  const { env, dispatches } = setup({ pendingAgeMs: 60_000 });

  await triggerBuild(CACHE_KEY, env, "1.2.3.4");

  assert.equal(dispatches.length, 0);
});

test("an expired pending marker is reclaimed, once, by concurrent callers", async () => {
  const { r2, env, dispatches } = setup({ pendingAgeMs: 3_700_000 });

  await Promise.all([
    triggerBuild(CACHE_KEY, env, "1.2.3.4"),
    triggerBuild(CACHE_KEY, env, "1.2.3.4"),
  ]);

  assert.equal(dispatches.length, 1);

  const marker = await r2.head(PENDING_KEY);
  assert.equal(marker.customMetadata.nonce, dispatches[0].build_nonce);
});
