import test from "node:test";
import assert from "node:assert/strict";

import { handleGet } from "../src/handlers.js";

const CACHE_KEY = "io-console-0.9.3-aarch64-linux-ruby4.0.gem";
const CHECKSUM_KEY = `${CACHE_KEY}.sha256`;
const CHECKSUM = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";

// Minimal R2 stand-in for reads. A key listed in failingKeys throws, the way a
// binding call does when R2 has a hiccup.
function bucket(objects, failingKeys = []) {
  return {
    async get(key) {
      if (failingKeys.includes(key)) throw new Error("R2 unavailable");
      if (!(key in objects)) return null;

      const body = objects[key];
      return { body, size: body.length, httpEtag: '"etag"', text: async () => body };
    },
  };
}

async function get(objects, failingKeys) {
  const env = { R2_BUCKET: bucket(objects, failingKeys) };
  return handleGet(CACHE_KEY, env, { waitUntil() {} }, "1.2.3.4");
}

test("a gem response carries its stored checksum", async () => {
  const response = await get({ [CACHE_KEY]: "gem-data", [CHECKSUM_KEY]: CHECKSUM });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Prebake-Sha256"), CHECKSUM);
  assert.equal(await response.text(), "gem-data");
});

test("a stored checksum ending in a newline is sent without it", async () => {
  const response = await get({ [CACHE_KEY]: "gem-data", [CHECKSUM_KEY]: `${CHECKSUM}\n` });

  assert.equal(response.headers.get("X-Prebake-Sha256"), CHECKSUM);
});

test("a gem without a stored checksum is served without the header", async () => {
  const response = await get({ [CACHE_KEY]: "gem-data" });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Prebake-Sha256"), null);
});

test("a malformed stored checksum is left out of the gem response", async () => {
  const response = await get({
    [CACHE_KEY]: "gem-data",
    [CHECKSUM_KEY]: `${CHECKSUM}\r\nX-Injected: yes`,
  });

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Prebake-Sha256"), null);
});

test("a failed checksum read still serves the gem", async (t) => {
  t.mock.method(console, "error", () => {});

  const response = await get({ [CACHE_KEY]: "gem-data" }, [CHECKSUM_KEY]);

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("X-Prebake-Sha256"), null);
  assert.equal(await response.text(), "gem-data");
});
