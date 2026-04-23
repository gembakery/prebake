# frozen_string_literal: true

require "rubygems/ext"
require "fileutils"
require "digest"
require_relative "cache_key"
require_relative "platform"
require_relative "extractor"
require_relative "elf_inspector"
require_relative "glibc"
require_relative "logger"

module Prebake
  module ExtBuilderPatch
    def build_extensions
      return super unless @spec.extensions.any?
      return super unless Prebake.enabled?
      return super unless Prebake.backend # nil if config failed

      if Prebake.optional_native_extension?(@spec.name) && !Prebake.libruby_available?
        Logger.warn "#{@spec.name}: native extension skipped (optional gem, libruby.so absent on static Ruby build)"
        install_without_native_extension
        return
      end

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
        unless portable_for_host?(cached_gem)
          # Binary is valid for other hosts; don't delete from backend.
          return super
        end

        installed = begin
          install_from_cache(cached_gem)
        rescue StandardError => e
          Logger.warn "Cache install failed for #{@spec.name}: #{e.message}, falling back to source build"
          false
        end

        unless installed
          Prebake.backend.delete(cache_key)
          return super
        end
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

    def portable_for_host?(gem_path)
      # Cache key already segregates platforms; portability checks only apply on linux.
      return true unless Glibc.linux?
      return true if Prebake.skip_portability_check?

      required = ElfInspector.required_glibc_for_gem(gem_path)
      unless Glibc.compatible?(required)
        Logger.warn "Cached #{@spec.name} requires glibc #{required}, host has #{Glibc.detected_version || 'unknown'}; falling back to source build"
        return false
      end

      if !Prebake.libruby_available? && ElfInspector.libruby_needed_for_gem?(gem_path)
        Logger.warn "Cached #{@spec.name} requires libruby.so (dynamic Ruby build) but this host has a static Ruby; falling back to source build"
        return false
      end

      true
    end

    def install_without_native_extension
      FileUtils.mkdir_p(File.dirname(@spec.gem_build_complete_path))
      FileUtils.touch(@spec.gem_build_complete_path)
    end

    def install_from_cache(gem_path)
      count = Extractor.install(gem_path, @spec)

      if count.zero?
        Logger.warn "No binaries found in cached gem for #{@spec.name}, falling back to source build"
        return false
      end

      FileUtils.mkdir_p(File.dirname(@spec.gem_build_complete_path))
      FileUtils.touch(@spec.gem_build_complete_path)
      true
    end
  end
end
