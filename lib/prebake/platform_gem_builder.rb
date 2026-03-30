# frozen_string_literal: true

require "rubygems/package"
require "fileutils"
require "digest"
require "tempfile"
require "securerandom"
require_relative "platform"
require_relative "logger"

module Prebake
  class PlatformGemBuilder
    attr_reader :checksum

    def initialize(spec)
      @spec = spec
      @checksum = nil
    end

    def build
      # Build in a temp directory; Dir.chdir is scoped to it to
      # isolate from Bundler's working directory.
      Dir.mktmpdir("prebake-build") do |build_dir|
        FileUtils.cp_r(File.join(@spec.gem_dir, "."), build_dir)

        platform_spec = build_platform_spec(build_dir)

        gem_file = nil
        Dir.chdir(build_dir) do
          gem_file = Gem::Package.build(platform_spec)
        end

        built_path = File.join(build_dir, gem_file)
        final = File.join(Dir.tmpdir, "prebake-built-#{SecureRandom.hex(16)}.gem")
        FileUtils.cp(built_path, final)

        @checksum = Digest::SHA256.file(final).hexdigest
        Logger.debug "Built #{gem_file} (SHA256: #{@checksum})"

        final
      end
    end

    private

    def build_platform_spec(build_dir)
      platform_spec = @spec.dup
      platform_spec.platform = Gem::Platform.new(Platform.generalized)
      platform_spec.extensions = []

      # Remove build-artifact binaries copied from gem_dir (they live at
      # wrong paths like ext/<name>/<name>.so).  The properly-installed
      # binaries are in extension_dir, placed there by `make install`.
      Dir.glob(File.join(build_dir, "**/*.{so,bundle,dll}")).each { |f| File.delete(f) }

      ext_dir = @spec.extension_dir
      if ext_dir && File.directory?(ext_dir)
        # Collect binaries at root and one level deep (e.g., nokogiri/nokogiri.so).
        binaries = Dir.glob(File.join(ext_dir, "*.{so,bundle,dll}")) +
                   Dir.glob(File.join(ext_dir, "*/*.{so,bundle,dll}"))

        # Ruby 4.0+ places compiled extensions in extension/<platform>/<abi>/
        # within extension_dir.  Collect these too, normalizing their paths
        # to root level so the cached gem is layout-agnostic.
        Dir.glob(File.join(ext_dir, "extension/*/*/*.{so,bundle,dll}")).each do |binary|
          relative = binary.delete_prefix("#{ext_dir}/")
          normalized = relative.sub(%r{\Aextension/[^/]+/[^/]+/}, "")
          # Skip if a root-level binary with the same name already exists
          next if binaries.any? { |b| b.delete_prefix("#{ext_dir}/") == normalized }

          binaries << binary
        end

        binaries.each do |binary|
          next if File.symlink?(binary)
          next if File.size(binary).zero?
          relative = binary.delete_prefix("#{ext_dir}/")
          # Normalize extension/<platform>/<abi>/ paths to root level
          relative = relative.sub(%r{\Aextension/[^/]+/[^/]+/}, "")
          dest = File.join(build_dir, relative)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(binary, dest)
        end
      end

      prefix = "#{build_dir}/"
      compiled = Dir.glob(File.join(build_dir, "**/*.{so,bundle,dll}"))
                    .map { |f| f.delete_prefix(prefix) }
      platform_spec.files = platform_spec.files | compiled

      platform_spec
    end
  end
end
