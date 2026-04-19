# frozen_string_literal: true

module Prebake
  module Logger
    LEVELS = { debug: 0, info: 1, warn: 2, silent: 3 }.freeze

    def self.level
      @level ||= LEVELS.fetch(ENV.fetch("PREBAKE_LOG_LEVEL", "silent").to_sym, 3)
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

      output "  [prebake] WARN: #{msg}"
    end

    def self.reset!
      @level = nil
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
