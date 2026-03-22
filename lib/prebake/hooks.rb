# frozen_string_literal: true

require_relative "async_publisher"
require_relative "logger"

module Prebake
  module Hooks
    def self.register!
      return unless defined?(Bundler::Plugin::API)

      Bundler::Plugin::API.hook("after-install") do |spec_install|
        next unless Prebake.push_enabled?
        next unless spec_install.state == :installed

        gem_spec = spec_install.spec
        next unless gem_spec.extensions.any?
        next unless gem_spec.platform.to_s == "ruby"
        next unless File.exist?(gem_spec.gem_build_complete_path)

        AsyncPublisher.enqueue(gem_spec, Prebake.backend)
      end

      Bundler::Plugin::API.hook("after-install-all") do |_deps|
        next unless Prebake.push_enabled?

        AsyncPublisher.wait_for_completion
      end

      Logger.debug "Hooks registered"
    end
  end
end
