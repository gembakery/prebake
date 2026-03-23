import { validateGemVersion } from "./validate-gem-version.js";

export const CACHE_KEY_REGEX =
  /^[a-zA-Z0-9_.-]+-[0-9.]+-[a-z0-9_-]+-ruby[0-9.]+\.gem$/;

export function parseCacheKey(cacheKey) {
  const match = cacheKey.match(
    /^(.+?)-(\d+\.\d+(?:\.\d+)?(?:\.\w+)*)-([a-z0-9_-]+)-ruby(\d+\.\d+)\.gem$/,
  );

  if (!match) return null;

  return {
    name: match[1],
    version: match[2],
    platform: match[3],
    rubyAbi: match[4],
  };
}

export async function triggerBuild(cacheKey, env, clientIp) {
  const parsed = parseCacheKey(cacheKey);
  if (!parsed) {
    console.error(`Cannot parse cache key: ${cacheKey}`);
    return;
  }

  const { success } = await env.BUILD_RATE_LIMITER.limit({ key: clientIp });
  if (!success) {
    console.log(`Build rate limit exceeded for ${clientIp}`);
    return;
  }

  const maxMonthlyBuilds = parseInt(env.MAX_MONTHLY_BUILDS, 10);
  if (Number.isNaN(maxMonthlyBuilds)) {
    console.error("MAX_MONTHLY_BUILDS is not configured or invalid");
    return;
  }

  const pendingKey = `_pending/${cacheKey}`;
  const monthKey = `_meta/monthly_builds/${new Date().toISOString().slice(0, 7)}`;

  const [existingPending, gemResponse, monthCounter] = await Promise.all([
    env.R2_BUCKET.head(pendingKey),
    fetch(`https://rubygems.org/api/v1/versions/${parsed.name}.json`),
    env.R2_BUCKET.get(monthKey),
  ]);

  if (existingPending) {
    const meta = existingPending.customMetadata;
    if (meta && meta.triggered_at) {
      const age = Date.now() - new Date(meta.triggered_at).getTime();
      if (age < 3600000) {
        console.log(
          `Build pending for ${cacheKey} (${Math.round(age / 1000)}s ago)`,
        );
        return;
      }
    }
  }

  const valid = await validateGemVersion(gemResponse, parsed);
  if (!valid) {
    if (existingPending) await env.R2_BUCKET.delete(pendingKey);
    return;
  }

  // Race-safe only under low concurrency; acceptable approximation for budget caps.
  const parsedCount = monthCounter
    ? parseInt(await monthCounter.text(), 10)
    : 0;
  const monthlyCount = Number.isNaN(parsedCount) ? 0 : parsedCount;
  if (monthlyCount >= maxMonthlyBuilds) {
    console.log(
      `Monthly build cap reached (${monthlyCount}/${maxMonthlyBuilds})`,
    );
    return;
  }

  const nonce = crypto.randomUUID();

  await env.R2_BUCKET.put(pendingKey, "", {
    customMetadata: { triggered_at: new Date().toISOString(), nonce },
  });

  const response = await fetch(
    `https://api.github.com/repos/${env.GITHUB_REPO}/actions/workflows/build-gem.yml/dispatches`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github.v3+json",
        "User-Agent": "prebake-worker",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        ref: "main",
        inputs: {
          gem_name: parsed.name,
          gem_version: parsed.version,
          platform: parsed.platform,
          ruby_abi: parsed.rubyAbi,
          build_nonce: nonce,
        },
      }),
    },
  );

  if (!response.ok) {
    const body = await response.text();
    console.error(`GitHub API error: ${response.status} ${body}`);
    await env.R2_BUCKET.delete(pendingKey);
  } else {
    await env.R2_BUCKET.put(monthKey, String(monthlyCount + 1));
    console.log(
      `Triggered build for ${cacheKey} (${monthlyCount + 1}/${maxMonthlyBuilds} this month)`,
    );
  }
}
