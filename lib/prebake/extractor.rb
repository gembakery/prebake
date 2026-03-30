# frozen_string_literal: true

require "rubygems/package"
require "fileutils"
require_relative "logger"

module Prebake
  module Extractor
    BINARY_EXTENSIONS = %w[.so .bundle .dll].freeze

    def self.install(gem_path, spec)
      Logger.debug "Extracting precompiled binaries from #{File.basename(gem_path)}"

      extracted_count = 0

      Dir.mktmpdir("prebake-extract") do |tmpdir|
        # Extract all files from the gem into a temp directory
        Gem::Package.new(gem_path).extract_files(tmpdir)

        # Copy only binary files (.so, .bundle, .dll) to extension_dir
        Dir.glob(File.join(tmpdir, "**/*.{so,bundle,dll}")).each do |binary|
          # Reject symlinks and empty files
          next if File.symlink?(binary)
          next if File.size(binary).zero?

          # Verify path is within tmpdir (prevent traversal)
          real_binary = File.realpath(binary)
          real_tmpdir = File.realpath(tmpdir)
          next unless real_binary.start_with?("#{real_tmpdir}/")

          relative = binary.sub("#{tmpdir}/", "")

          # Normalize paths from cached gems where binaries were packaged
          # from gem_dir build artifacts or dirty extension_dirs.
          # ext/<name>/<name>.so               → <name>.so       (build artifact)
          # lib/<name>/<name>.so               → <name>/<name>.so (gem lib path)
          # extension/<platform>/<ver>/<name>.so → <name>.so       (extension_dir artifact)
          relative = relative.sub(%r{\Aext/[^/]+/}, "") if relative.start_with?("ext/")
          relative = relative.sub(%r{\Alib/}, "") if relative.start_with?("lib/")
          relative = relative.sub(%r{\Aextensions?/[^/]+/[^/]+/}, "") if relative.start_with?("extension/", "extensions/")

          dest = File.join(spec.extension_dir, relative)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(binary, dest)
          extracted_count += 1
        end
      end

      Logger.info "Installed precompiled #{File.basename(gem_path)} " \
                  "(#{extracted_count} binary files)"

      extracted_count
    rescue StandardError => e
      Logger.warn "Extraction failed for #{File.basename(gem_path)}: #{e.message}"
      raise
    end
  end
end
