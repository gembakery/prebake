# frozen_string_literal: true

module Prebake
  module Platform
    NORMALIZATIONS = [
      [/\Aarm64-darwin(-\d+)?\z/, "arm64-darwin"],
      [/\Ax86_64-darwin(-\d+)?\z/, "x86_64-darwin"],
      [/\Ax86_64-linux-musl\z/, "x86_64-linux-musl"],
      [/\Aaarch64-linux-musl\z/, "aarch64-linux-musl"],
      [/\Ax86_64-linux(-gnu)?\z/, "x86_64-linux"],
      [/\Aaarch64-linux(-gnu)?\z/, "aarch64-linux"]
    ].freeze

    def self.normalize(platform_string)
      NORMALIZATIONS.each do |pattern, normalized|
        return normalized if platform_string.match?(pattern)
      end

      platform_string
    end

    def self.generalized
      platform = Gem::Platform.local
      base = normalize(platform.to_s)

      # On Linux, detect musl vs glibc - they produce incompatible binaries.
      # Gem::Platform.local may report "gnu" even on musl systems, so we
      # detect explicitly.
      if platform.os == "linux" && !base.include?("musl") && musl?
        base.sub(/\z/, "-musl")
      else
        base
      end
    end

    def self.musl?
      return false unless RUBY_PLATFORM.include?("linux")

      File.exist?("/lib/ld-musl-x86_64.so.1") ||
        File.exist?("/lib/ld-musl-aarch64.so.1") ||
        begin
          `ldd --version 2>&1`.include?("musl")
        rescue StandardError
          false
        end
    end
  end
end
