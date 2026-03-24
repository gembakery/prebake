# frozen_string_literal: true

module Prebake
  module Logger
    LEVELS = { debug: 0, info: 1, warn: 2 }.freeze

    def self.level
      LEVELS.fetch(ENV.fetch("PREBAKE_LOG_LEVEL", "warn").to_sym, 1)
    end

    def self.debug(msg)
      return unless level <= 0

      output "  [prebake] #{msg}"
    end

    def self.info(msg)
      return unless level <= 1

      output "  [prebake] #{msg}"
    end

    def self.warn(msg)
      return unless level <= 2
      return if darwin_with_default_host?

      output "  [prebake] WARN: #{msg}"
    end

    def self.reset!
      remove_instance_variable(:@darwin_with_default_host) if instance_variable_defined?(:@darwin_with_default_host)
    end

    private_class_method def self.darwin_with_default_host?
      return @darwin_with_default_host if defined?(@darwin_with_default_host)

      @darwin_with_default_host =
        RUBY_PLATFORM.include?("darwin") &&
        Prebake.backend_type == "http" &&
        (url = ENV.fetch("PREBAKE_HTTP_URL", nil)
         url.nil? || url.chomp("/") == Prebake::DEFAULT_HTTP_URL)
    end

    def self.output(msg)
      if defined?(Bundler) && Bundler.respond_to?(:ui)
        Bundler.ui.info msg
      else
        Kernel.warn msg
      end
    end
  end
end
