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

      # Scan known-broken nested patterns
      nested = Dir.glob(File.join(ext_dir, "extension", "*", "*", BINARY_GLOB))
      nested.concat(Dir.glob(File.join(ext_dir, "lib", BINARY_GLOB)))

      nested.each do |binary|
        next if File.symlink?(binary)
        next if File.size(binary).zero?

        dest = File.join(ext_dir, File.basename(binary))
        next if File.exist?(dest)

        FileUtils.cp(binary, dest)
        Logger.info "Validator: copied #{File.basename(binary)} to #{ext_dir}"
      end
    end
  end
end
