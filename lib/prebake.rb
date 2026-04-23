# frozen_string_literal: true

require_relative "prebake/logger"

module Prebake
  class Error < StandardError; end

  # major.minor only - ABI is stable across patch versions
  RUBY_ABI_VERSION = "#{RbConfig::CONFIG['MAJOR']}.#{RbConfig::CONFIG['MINOR']}".freeze
  DEFAULT_HTTP_URL = "https://gems.prebake.in"

  # Gems whose native extensions are entirely optional — the gem runs correctly in pure Ruby
  # mode when the extension can't be loaded. On static Ruby builds (e.g. Paketo MRI buildpack)
  # libruby.so is absent, so compiled extensions that dynamically link against it would crash
  # at load time. Prebake skips the extension for these gems instead of installing a broken .so.
  # Extend at runtime via PREBAKE_OPTIONAL_NATIVE_EXTENSIONS=gem1,gem2.
  OPTIONAL_NATIVE_EXTENSIONS_DEFAULT = %w[bootsnap].freeze

  @backend_mutex = Mutex.new

  def self.enabled?
    ENV.fetch("PREBAKE_ENABLED", "true") != "false"
  end

  def self.push_enabled?
    enabled? && ENV.fetch("PREBAKE_PUSH_ENABLED", "false") == "true"
  end

  def self.skip_portability_check?
    ENV.fetch("PREBAKE_SKIP_PORTABILITY_CHECK", "false") == "true"
  end

  def self.max_glibc
    ENV.fetch("PREBAKE_MAX_GLIBC", nil)
  end

  def self.optional_native_extensions
    extra = ENV.fetch("PREBAKE_OPTIONAL_NATIVE_EXTENSIONS", "")
               .split(",").map(&:strip).reject(&:empty?)
    (OPTIONAL_NATIVE_EXTENSIONS_DEFAULT + extra).uniq
  end

  def self.optional_native_extension?(gem_name)
    optional_native_extensions.include?(gem_name)
  end

  # Returns true when Ruby's shared library (libruby.so / libruby.dylib) is present on disk.
  # Static Ruby builds (e.g. Paketo MRI buildpack) omit the shared library, so native
  # extensions compiled with a dynamic link to libruby will fail to load at runtime.
  def self.libruby_available?
    libruby_so = RbConfig::CONFIG["LIBRUBY_SO"]
    return false if libruby_so.nil? || libruby_so.empty?

    File.exist?(File.join(RbConfig::CONFIG["libdir"], libruby_so))
  end

  def self.backend
    return @backend if defined?(@backend_loaded)

    @backend_mutex.synchronize do
      return @backend if defined?(@backend_loaded)

      @backend_loaded = true
      @backend = load_backend
    end
  rescue Error => e
    Logger.warn "Backend initialization failed: #{e.message}. Plugin disabled for this session."
    @backend = nil
  end

  def self.backend=(backend)
    @backend_loaded = true
    @backend = backend
  end

  def self.reset!
    remove_instance_variable(:@backend_loaded) if defined?(@backend_loaded)
    remove_instance_variable(:@backend) if defined?(@backend)
  end

  def self.setup!
    return unless enabled?

    require_relative "prebake/ext_builder_patch"
    Gem::Ext::Builder.prepend(ExtBuilderPatch)

    require_relative "prebake/hooks"
    Hooks.register!

    Logger.info "Plugin active (backend: #{backend_type})"
  rescue StandardError => e
    Logger.warn "Failed to initialize: #{e.message}"
  end

  def self.backend_type
    ENV.fetch("PREBAKE_BACKEND", "http")
  end

  class << self
    private

    def load_backend
      case backend_type
      when "gemstash"
        require_relative "prebake/backends/gemstash"
        url = ENV.fetch("PREBAKE_GEMSTASH_URL") { raise Error, "PREBAKE_GEMSTASH_URL is required" }
        key = ENV.fetch("PREBAKE_GEMSTASH_KEY", nil)
        Backends::Gemstash.new(url:, key:)
      when "s3"
        require_relative "prebake/backends/s3"
        bucket = ENV.fetch("PREBAKE_S3_BUCKET") { raise Error, "PREBAKE_S3_BUCKET is required" }
        Backends::S3.new(
          bucket:,
          region: ENV.fetch("PREBAKE_S3_REGION", "us-east-1"),
          prefix: ENV.fetch("PREBAKE_S3_PREFIX", "prebake")
        )
      when "http"
        require_relative "prebake/backends/http"
        url = ENV.fetch("PREBAKE_HTTP_URL", DEFAULT_HTTP_URL)
        Backends::Http.new(url:, token: ENV.fetch("PREBAKE_HTTP_TOKEN", nil))
      else
        raise Error, "Unknown backend: #{backend_type}. Use gemstash, s3, or http."
      end
    end
  end
end
