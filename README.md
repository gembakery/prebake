<div align="center">
  <img width="256" height="256" src="https://github.com/user-attachments/assets/a5b363e6-9ecf-4723-957c-0ea993b0bd28" />
	<h1>Prebake</h1>
	<p>
		<b>Stop compiling. Start installing. Prebake your native gems.</b>
	</p>
	<br>
</div>

Prebake is a Bundler plugin that speeds up `bundle install` by skipping native gem compilation. Instead of compiling C extensions from source every time, it fetches precompiled binaries from a shared cache. If the cache doesn't have it yet, Bundler compiles normally and the result is cached for everyone.

## Why prebake?

Native gems like **puma**, **nokogiri**, **pg**, **grpc**, **bootsnap**, **sassc**, **nio4r**, **prism**, and **msgpack** compile C extensions on every fresh `bundle install`. On a typical Rails app, this adds **2-3 minutes** to every cold install, including in CI, on new developer machines, and during deployments.

Prebake eliminates this. Once a gem is compiled by anyone, it's cached and served as a prebuilt binary to everyone else. The more people use it, the faster it gets.

## Who is this for?

- **Ruby/Rails teams** tired of slow `bundle install` in CI
- **Monorepos and multi-app setups** where the same gems are compiled repeatedly across projects
- **Open source projects** that want faster contributor onboarding
- **Anyone on Ruby 3.2+** using native gems on Linux or macOS

## Installation

Add one line to your `Gemfile`:

```ruby
plugin "prebake"
```

Then run:

```bash
bundle install
```

That's it. No other changes needed. Bundler downloads and activates the plugin automatically. The default `http` backend uses the hosted cache at `https://gems.prebake.in`; you do not need to set `PREBAKE_HTTP_URL` unless you want a different server.

## Quick start

### Self-hosted with Gemstash

```bash
export PREBAKE_BACKEND=gemstash
export PREBAKE_GEMSTASH_URL=http://localhost:9292
export PREBAKE_PUSH_ENABLED=true
bundle install
```

### Self-hosted with S3-compatible storage

```bash
export PREBAKE_BACKEND=s3
export PREBAKE_S3_BUCKET=my-prebake-cache
export PREBAKE_PUSH_ENABLED=true
bundle install
```

## Configuration

All configuration is done through environment variables. No code changes required.

| Variable | Default | Description |
|---|---|---|
| `PREBAKE_ENABLED` | `true` | Set to `false` to turn the plugin off without editing the `Gemfile` (for example in CI or a one-off `bundle install`). Removing `plugin "prebake"` also disables it. |
| `PREBAKE_PUSH_ENABLED` | `false` | Set to `true` to enable local build + push (for self-hosted setups). |
| `PREBAKE_BACKEND` | `http` | Cache backend: `http`, `s3` (any S3-compatible: AWS S3, Cloudflare R2, Backblaze B2, MinIO), or `gemstash`. |
| `PREBAKE_HTTP_URL` | `https://gems.prebake.in` | URL of the prebake cache service when using the `http` backend. |
| `PREBAKE_HTTP_TOKEN` | _(none)_ | Optional Bearer token sent with HTTP requests. Use this when your cache server requires authentication (private or self-hosted HTTP endpoints). |
| `PREBAKE_S3_BUCKET` | _(required for s3)_ | Bucket name (AWS S3, Cloudflare R2, Backblaze B2, MinIO, etc.). |
| `PREBAKE_S3_REGION` | `us-east-1` | Bucket region. |
| `PREBAKE_S3_PREFIX` | `prebake` | Key prefix (folder) within the bucket. |
| `PREBAKE_GEMSTASH_URL` | _(required for gemstash)_ | Gemstash server URL. |
| `PREBAKE_GEMSTASH_KEY` | _(none)_ | Gemstash API key. |
| `PREBAKE_LOG_LEVEL` | `silent` | Log verbosity: `debug`, `info`, `warn`, `silent`. Silent by default since prebake is an enhancement — all failures fall back to source builds. Set to `warn` to diagnose cache misses. |
| `PREBAKE_MAX_GLIBC` | _(none)_ | Publisher guard. When set (e.g. `2.28`), prebake refuses to push a built gem whose binaries require a newer glibc than this. Prevents self-hosted caches from being poisoned by a modern build host for older consumers. |
| `PREBAKE_SKIP_PORTABILITY_CHECK` | `false` | Consumer guard. Set to `true` to skip the glibc compatibility check on cache hits (escape hatch for unusual environments). |
| `PREBAKE_OPTIONAL_NATIVE_EXTENSIONS` | _(none)_ | Comma-separated gem names whose native extensions are entirely optional (gem works in pure-Ruby mode without them). On a static Ruby build (libruby.so absent), prebake skips the native extension for these gems instead of installing a broken `.so`. |

## How it works

### Fetching precompiled gems (consumer)

1. Bundler starts installing a gem with native extensions (e.g., `puma`, `nokogiri`, `pg`).
2. Prebake intercepts `Gem::Ext::Builder#build_extensions` before compilation starts.
3. A cache key is generated from the gem name, version, platform (for example `aarch64-linux`), and Ruby ABI version (e.g., `4.0`).
4. The plugin checks the configured backend for a precompiled binary matching that key.
5. **Cache hit**: the prebuilt `.so`/`.bundle` files are extracted directly, with no compiler needed.
6. **Cache miss**: Bundler compiles from source as usual (no impact, same as without the plugin).

### Publishing compiled gems (publisher)

When `PREBAKE_PUSH_ENABLED=true` (for self-hosted setups):

1. After all gems are installed, the plugin identifies gems that were freshly compiled from source.
2. For each, it builds a platform-specific `.gem` file and computes a SHA-256 checksum.
3. The gem and checksum are uploaded to the backend in the background.
4. Future `bundle install` runs by anyone on the same platform get the precompiled version.

## Supported platforms (cloud service)

| Platform | Architecture | OS |
|---|---|---|
| `x86_64-linux` | x86-64 | Linux (glibc) |
| `aarch64-linux` | ARM64 | Linux (glibc) |
| `x86_64-linux-musl` | x86-64 | Linux (musl/Alpine) |
| `aarch64-linux-musl` | ARM64 | Linux (musl/Alpine) |

Other platforms are supported for self-hosted setups with `PREBAKE_PUSH_ENABLED=true`. The first `bundle install` compiles locally and caches the result for others.

## Backend setup

### HTTP (default)

Works with the hosted prebake service at `gems.prebake.in` or any custom HTTP server implementing `GET/PUT/HEAD /gems/:key`. By default no environment variables are required. To point at another server:

```bash
export PREBAKE_BACKEND=http
export PREBAKE_HTTP_URL=https://gems.prebake.in
```

### S3-compatible storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO)

Works with any S3-compatible storage. Requires the `aws-sdk-s3` gem.

```bash
export PREBAKE_BACKEND=s3
export PREBAKE_S3_BUCKET=my-prebake-cache
export PREBAKE_S3_REGION=us-east-1
export PREBAKE_PUSH_ENABLED=true
```

For non-AWS providers, set the endpoint:

```bash
# Cloudflare R2
export AWS_ENDPOINT_URL=https://<account-id>.r2.cloudflarestorage.com

# Backblaze B2
export AWS_ENDPOINT_URL=https://s3.<region>.backblazeb2.com

# MinIO (self-hosted)
export AWS_ENDPOINT_URL=http://minio.internal:9000
```

Credentials are resolved via the standard AWS SDK chain (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, IAM role, `~/.aws/credentials`, etc.).

### Gemstash

[Gemstash](https://github.com/rubygems/gemstash) is the official RubyGems caching server. Prebake stores precompiled gems as private gems.

```bash
export PREBAKE_BACKEND=gemstash
export PREBAKE_GEMSTASH_URL=http://gemstash.internal:9292
export PREBAKE_GEMSTASH_KEY=my-api-key
export PREBAKE_PUSH_ENABLED=true
```

## Portability (glibc)

On Linux, shared libraries built against a newer glibc won't load on hosts with an older glibc. Prebake's cache key includes the platform and Ruby ABI but not the glibc version, which matches how rubygems.org's precompiled gems work — but in self-hosted setups the publisher and consumers may run very different distros.

Prebake addresses this with two guards:

- **Consumer-side (automatic)**: on a cache hit, prebake inspects the cached gem's `.so` files via `objdump -T` and reads the highest `GLIBC_X.Y` symbol version required. If the host's glibc (from `ldd --version`) is older, the cache hit is skipped and Bundler compiles from source. The cached binary is **not** deleted from the backend — it's still valid for other hosts. Set `PREBAKE_SKIP_PORTABILITY_CHECK=true` to disable.
- **Publisher-side (opt-in)**: set `PREBAKE_MAX_GLIBC=2.28` (or similar) on publish-enabled hosts. Prebake refuses to push a built gem whose binaries require a newer glibc than that floor. Nothing is enforced when the env var is unset.

Recommended values for `PREBAKE_MAX_GLIBC`:

| Baseline | glibc |
|---|---|
| Ubuntu 20.04 / RHEL 8 | `2.28` |
| Ubuntu 22.04 / Debian 12 | `2.35` |
| Ubuntu 24.04 | `2.39` |

Darwin and musl (Alpine) consumers bypass the check — the platform cache key already segregates those hosts.

## Portability (static Ruby)

Some Ruby deployments — notably the [Paketo MRI buildpack](https://github.com/paketo-buildpacks/mri) — link Ruby as a static binary and omit `libruby.so`. Native extensions compiled against a dynamic Ruby carry a `NEEDED libruby` dynamic dependency and will crash at load time on these hosts.

Prebake detects this automatically and applies two guards:

- **Consumer-side (automatic)**: on a cache hit, prebake inspects the cached gem's `.so` files via `objdump -p` and checks for a `NEEDED libruby` entry. If found and `libruby.so` is absent on the host, the cache hit is skipped and Bundler compiles from source. The cached binary is **not** deleted — it remains valid for dynamic-Ruby hosts.
- **Publisher-side (automatic)**: when `PREBAKE_PUSH_ENABLED=true`, prebake checks each freshly-built gem before uploading. If the binary links against `libruby.so` and the current host is a static Ruby build, the push is skipped. The binary would be broken on static hosts and is not representative of what dynamic hosts need.

### Optional native extensions

Some gems have entirely optional native extensions — they fall back to pure-Ruby mode when the extension isn't present. On a static Ruby host, you can tell prebake to skip the native extension build rather than compile a `.so` that may not load correctly:

```bash
export PREBAKE_OPTIONAL_NATIVE_EXTENSIONS=mygem,othergem
```

For gems on this list, prebake skips the native extension build entirely on static Ruby hosts and marks the gem as installed in pure-Ruby mode. No compilation, no broken `.so`.

> **Note:** Only add gems that genuinely support pure-Ruby fallback. Gems like bootsnap (1.18+) require their native extension unconditionally — adding them here produces a broken install.

## Frequently asked questions

### Does this work with Ruby 4.0?
Yes. Prebake is designed for Ruby 3.2+ and fully supports Ruby 4.0. Cache keys include the Ruby ABI version so gems compiled for Ruby 4.0 are never mixed with Ruby 3.3.

### Is this safe? Can someone inject malicious binaries?
The hosted service only builds from rubygems.org; users cannot push binaries. For self-hosted setups, SHA-256 checksums are verified on download.

### Does this replace Gemstash?
No. Gemstash caches all gems (download proxy). Prebake only handles native extension compilation. They work great together: Gemstash speeds up downloads, prebake eliminates compilation.

### What gems benefit from this?
Any gem with native C extensions: puma, nokogiri, pg, grpc, bootsnap, sassc, nio4r, prism, msgpack, bcrypt, ffi, eventmachine, websocket-driver, oj, redcarpet, and many more.

## Troubleshooting

Prebake is silent by default — if a cache entry can't be used, it transparently falls back to compiling from source. To see what the plugin is doing (cache hits/misses, push failures, fallbacks), raise the log level:

```bash
PREBAKE_LOG_LEVEL=warn bundle install   # surface warnings
PREBAKE_LOG_LEVEL=debug bundle install  # full diagnostics
```

**Common issues:**

- `Backend initialization failed`: check your backend URL and credentials. The plugin disables itself gracefully and Bundler continues normally.
- `Checksum mismatch`: the downloaded binary doesn't match the stored SHA-256. The plugin automatically falls back to compiling from source.
- `LoadError: cannot load such file -- bigdecimal.so` (Ruby 4.0): RubyGems 4 [stopped copying `.so` files into `lib/`](https://github.com/ruby/rubygems/pull/9240), and Bundler 2.5.x doesn't properly resolve the new extension directory layout. This is a Bundler bug, not a prebake issue. Fix it by upgrading Bundler: `gem install bundler && bundle update --bundler`. If you're using `ruby/setup-ruby` with `bundler-cache: true` in CI, also delete the stale Actions cache so the extensions are rebuilt with the new Bundler.
- To disable for a single run: `PREBAKE_ENABLED=false bundle install`.

## Compatibility

- **Ruby**: 3.2, 3.3, 3.4, 4.0+
- **Bundler**: 2.4+ (Ruby 4.0 users should use Bundler 4.x — see [Troubleshooting](#troubleshooting))
- **OS**: Linux (x86_64, aarch64, glibc and musl) via cloud service; other platforms via self-hosted

## License

MIT
