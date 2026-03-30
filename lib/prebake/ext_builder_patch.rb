# frozen_string_literal: true

require "rubygems/ext"
require "fileutils"
require "digest"
require_relative "cache_key"
require_relative "platform"
require_relative "extractor"
require_relative "logger"

module Prebake
  module ExtBuilderPatch
    def build_extensions
      return super unless @spec.extensions.any?
      return super unless Prebake.enabled?
      return super unless Prebake.backend # nil if config failed

      platform = Platform.generalized
      cache_key = CacheKey.for(@spec.name, @spec.version.to_s, platform)

      expected_checksum = Prebake.backend.fetch_checksum(cache_key)

      if expected_checksum.nil? && Prebake.backend.checksums_supported?
        trigger_rebuild(cache_key)
        return super
      end

      begin
        cached_gem = Prebake.backend.fetch(cache_key)
      rescue StandardError => e
        Logger.debug "Cache fetch error for #{@spec.name}: #{e.message}"
        return super
      end

      unless cached_gem
        Logger.debug "Cache miss for #{cache_key}"
        return super
      end

      if verify_checksum(cache_key, expected_checksum, cached_gem)
        install_from_cache(cached_gem)
      else
        super
      end
    ensure
      FileUtils.rm_f(cached_gem) if cached_gem
    end

    private

    def trigger_rebuild(cache_key)
      Logger.warn "No checksum available for #{cache_key}, removing cached gem"
      Prebake.backend.delete(cache_key)
      # GET triggers the worker to dispatch a rebuild via GH Actions on cache miss
      trigger_path = Prebake.backend.fetch(cache_key)
      FileUtils.rm_f(trigger_path) if trigger_path
    end

    def verify_checksum(cache_key, expected, gem_path)
      return true if expected.nil?

      actual = Digest::SHA256.file(gem_path).hexdigest
      if actual == expected
        true
      else
        Logger.warn "Checksum mismatch for #{cache_key}: expected #{expected}, got #{actual}"
        false
      end
    end

    def install_from_cache(gem_path)
      Logger.info "Installing precompiled #{@spec.name}-#{@spec.version}"
      Extractor.install(gem_path, @spec)
      FileUtils.mkdir_p(File.dirname(@spec.gem_build_complete_path))
      FileUtils.touch(@spec.gem_build_complete_path)
    end
  end
end
