# frozen_string_literal: true

require "fileutils"
require_relative "platform_gem_builder"
require_relative "cache_key"
require_relative "platform"
require_relative "logger"

module Prebake
  module AsyncPublisher
    @pending_specs = []
    @mutex = Mutex.new

    def self.reset!
      @mutex.synchronize { @pending_specs.clear }
    end

    def self.enqueue(spec, backend)
      @mutex.synchronize { @pending_specs << [spec, backend] }
    end

    def self.wait_for_completion(timeout: 120)
      specs = @mutex.synchronize { @pending_specs.dup }
      return if specs.empty?

      Logger.info "Building #{specs.size} platform gem(s)..."

      # Build serially (Dir.chdir is not thread-safe in Ruby 4.0)
      built_gems = specs.filter_map do |spec, backend|
        build_gem(spec, backend)
      end

      if built_gems.any?
        Logger.info "Pushing #{built_gems.size} gem(s) in background..."

        # Push in parallel (just HTTP, no chdir needed)
        push_threads = built_gems.map do |gem_path, cache_key, checksum, backend|
          Thread.new do
            backend.push(gem_path, cache_key, checksum)
          rescue StandardError => e
            Logger.warn "Push failed for #{cache_key}: #{e.message}"
          ensure
            FileUtils.rm_f(gem_path)
          end
        end

        push_threads.each { |t| t.join(timeout) }
      end

      Logger.info "All pushes complete."

      @mutex.synchronize { @pending_specs.clear }
    end

    def self.build_gem(spec, backend)
      platform = Platform.generalized
      cache_key = CacheKey.for(spec.name, spec.version.to_s, platform)

      if backend.exists?(cache_key)
        Logger.debug "#{cache_key} already cached, skipping"
        return nil
      end

      builder = PlatformGemBuilder.new(spec)
      gem_path = builder.build
      checksum = builder.checksum

      Logger.debug "Built #{cache_key}"
      [gem_path, cache_key, checksum, backend]
    rescue StandardError => e
      Logger.warn "Error building #{spec.name}: #{e.message}"
      nil
    end

    private_class_method :build_gem
  end
end
