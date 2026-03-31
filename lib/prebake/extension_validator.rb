# frozen_string_literal: true

require "fileutils"
require_relative "logger"

module Prebake
  module ExtensionValidator
    BINARY_GLOB = "*.{so,bundle,dll}"

    def self.validate(spec)
      ext_dir = spec.extension_dir
      return unless File.exist?(File.join(ext_dir, ".prebake"))

      # Fast path: root-level binaries already present
      return if Dir.glob(File.join(ext_dir, BINARY_GLOB)).any?
    end
  end
end
