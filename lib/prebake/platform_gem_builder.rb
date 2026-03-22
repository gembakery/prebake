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

      prefix = "#{build_dir}/"
      compiled = Dir.glob(File.join(build_dir, "**/*.{so,bundle,dll}"))
                    .map { |f| f.delete_prefix(prefix) }
      platform_spec.files = platform_spec.files | compiled

      platform_spec
    end
  end
end
