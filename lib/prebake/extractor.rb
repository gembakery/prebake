# frozen_string_literal: true

require "rubygems/package"
require "fileutils"
require_relative "logger"

module Prebake
  module Extractor
    def self.install(gem_path, spec)
      Logger.debug "Extracting precompiled binaries from #{File.basename(gem_path)}"

      extracted_count = 0

      Dir.mktmpdir("prebake-extract") do |tmpdir|
        # Extract all files from the gem into a temp directory
        Gem::Package.new(gem_path).extract_files(tmpdir)

        # Copy only binary files (.so, .bundle, .dll) to extension_dir
        Dir.glob(File.join(tmpdir, "**/*.{so,bundle,dll}")).each do |binary|
          next unless safe_binary?(binary, tmpdir)

          dest = File.join(spec.extension_dir, normalized_path(binary, tmpdir))
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(binary, dest)
          extracted_count += 1
        end
      end

      # Mark this extension_dir as prebake-managed for post-install validation
      FileUtils.touch(File.join(spec.extension_dir, ".prebake")) if extracted_count.positive?

      Logger.info "Installed precompiled #{File.basename(gem_path)} " \
                  "(#{extracted_count} binary files)"

      extracted_count
    rescue StandardError => e
      Logger.warn "Extraction failed for #{File.basename(gem_path)}: #{e.message}"
      raise
    end

    # Reject symlinks, empty files, and anything resolving outside tmpdir
    # (path traversal via a crafted gem).
    def self.safe_binary?(binary, tmpdir)
      return false if File.symlink?(binary)
      return false if File.empty?(binary)

      File.realpath(binary).start_with?("#{File.realpath(tmpdir)}/")
    end

    # Normalize paths from cached gems where binaries were packaged from
    # gem_dir build artifacts or dirty extension_dirs.
    # ext/<name>/<name>.so                 → <name>.so        (build artifact)
    # lib/<name>/<name>.so                 → <name>/<name>.so (gem lib path)
    # extension/<platform>/<ver>/<name>.so → <name>.so        (extension_dir artifact)
    def self.normalized_path(binary, tmpdir)
      relative = binary.sub("#{tmpdir}/", "")
      relative = relative.sub(%r{\Aext/[^/]+/}, "") if relative.start_with?("ext/")
      relative = relative.sub(%r{\Alib/}, "") if relative.start_with?("lib/")
      return relative unless relative.start_with?("extension/", "extensions/")

      relative.sub(%r{\Aextensions?/[^/]+/[^/]+/}, "")
    end
  end
end
