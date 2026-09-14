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
      copy_installed_binaries(ext_dir, build_dir) if ext_dir && File.directory?(ext_dir)

      prefix = "#{build_dir}/"
      compiled = Dir.glob(File.join(build_dir, "**/*.{so,bundle,dll}"))
                    .map { |f| f.delete_prefix(prefix) }
      platform_spec.files = platform_spec.files | compiled

      platform_spec
    end

    def copy_installed_binaries(ext_dir, build_dir)
      installed_binaries(ext_dir).each do |binary|
        next if File.symlink?(binary)
        next if File.empty?(binary)

        dest = File.join(build_dir, root_level_path(binary, ext_dir))
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(binary, dest)
      end
    end

    # Binaries at root and one level deep (e.g., nokogiri/nokogiri.so), plus the
    # extension/<platform>/<abi>/ layout Ruby 4.0+ installs into.  A nested
    # binary is skipped when a root-level one already claims its normalized
    # path, so the cached gem stays layout-agnostic.
    def installed_binaries(ext_dir)
      binaries = Dir.glob(File.join(ext_dir, "*.{so,bundle,dll}")) +
                 Dir.glob(File.join(ext_dir, "*/*.{so,bundle,dll}"))

      Dir.glob(File.join(ext_dir, "extension/*/*/*.{so,bundle,dll}")).each do |binary|
        normalized = root_level_path(binary, ext_dir)
        next if binaries.any? { |b| b.delete_prefix("#{ext_dir}/") == normalized }

        binaries << binary
      end

      binaries
    end

    def root_level_path(binary, ext_dir)
      binary.delete_prefix("#{ext_dir}/").sub(%r{\Aextension/[^/]+/[^/]+/}, "")
    end
  end
end
