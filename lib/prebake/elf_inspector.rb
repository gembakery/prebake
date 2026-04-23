# frozen_string_literal: true

require "open3"
require "tempfile"
require "tmpdir"
require "rubygems/package"
require_relative "logger"

module Prebake
  module ElfInspector
    def self.required_glibc_for_gem(gem_path)
      Dir.mktmpdir("prebake-portability") do |tmpdir|
        Gem::Package.new(gem_path).extract_files(tmpdir)
        versions = Dir.glob(File.join(tmpdir, "**/*.{so,bundle,dll}")).filter_map do |binary|
          next if File.symlink?(binary) || File.size(binary).zero?

          required_glibc(binary)
        end
        return nil if versions.empty?

        versions.max_by { |v| Gem::Version.new(v) }
      end
    rescue StandardError => e
      # Malformed gem, missing objdump, or I/O error — treat as unknown, let
      # downstream extraction catch real corruption.
      Logger.debug "Portability inspection failed for #{File.basename(gem_path)}: #{e.message}"
      nil
    end

    def self.required_glibc(path)
      return nil unless File.exist?(path)

      output = run_objdump(path)
      return nil if output.nil? || output.empty?

      parse_glibc_version(output)
    end

    def self.parse_glibc_version(output)
      versions = output.scan(/GLIBC_(\d+(?:\.\d+)+)/).flatten
      return nil if versions.empty?

      versions.max_by { |v| Gem::Version.new(v) }
    end

    def self.libruby_needed_for_gem?(gem_path)
      Dir.mktmpdir("prebake-libruby") do |tmpdir|
        Gem::Package.new(gem_path).extract_files(tmpdir)
        Dir.glob(File.join(tmpdir, "**/*.{so,bundle,dll}")).any? do |binary|
          next false if File.symlink?(binary) || File.size(binary).zero?

          libruby_needed?(binary)
        end
      end
    rescue StandardError => e
      Logger.debug "libruby inspection failed for #{File.basename(gem_path)}: #{e.message}"
      false
    end

    def self.libruby_needed?(path)
      needed_libraries(path).any? { |lib| lib.start_with?("libruby") }
    end

    def self.needed_libraries(path)
      return [] unless File.exist?(path)

      out, status = Open3.capture2e("objdump", "-p", path)
      return [] unless status.success?

      out.scan(/NEEDED\s+(\S+)/).flatten
    rescue Errno::ENOENT
      []
    end

    def self.run_objdump(path)
      out, status = Open3.capture2e("objdump", "-T", path)
      return nil unless status.success?

      out
    rescue Errno::ENOENT
      nil
    end
  end
end
