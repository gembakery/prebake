# frozen_string_literal: true

require "open3"

module Prebake
  module Glibc
    GNU_LIBC_PATTERN = /GLIBC\s+(\d+(?:\.\d+)+)|GNU libc[^\n]*\s(\d+(?:\.\d+)+)/

    def self.compatible?(required)
      return true unless linux?
      return true if required.nil?

      detected = detected_version
      return false if detected.nil?

      Gem::Version.new(detected) >= Gem::Version.new(required)
    end

    def self.detected_version
      return @detected_version if defined?(@detected_version)

      output = run_ldd
      @detected_version = output ? parse_version(output) : nil
    end

    def self.parse_version(output)
      match = output.match(GNU_LIBC_PATTERN)
      match && (match[1] || match[2])
    end

    def self.linux?
      RUBY_PLATFORM.include?("linux")
    end

    def self.reset!
      remove_instance_variable(:@detected_version) if defined?(@detected_version)
    end

    def self.run_ldd
      out, status = Open3.capture2e("ldd", "--version")
      return nil unless status.success?

      out
    rescue Errno::ENOENT
      nil
    end
  end
end
