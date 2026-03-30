# frozen_string_literal: true

require "test_helper"
require "prebake/platform_gem_builder"
require "rubygems/package"
require "fileutils"

class PlatformGemBuilderTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_builds_platform_gem_with_compiled_binaries
    spec = create_installed_gem_with_extension

    builder = Prebake::PlatformGemBuilder.new(spec)
    gem_path = builder.build

    assert gem_path
    assert File.exist?(gem_path)
    assert_match(/\.gem\z/, gem_path)

    # Verify platform gem contents
    package = Gem::Package.new(gem_path)
    assert_equal Gem::Platform.local.os, package.spec.platform.os
    assert_empty package.spec.extensions
  ensure
    FileUtils.rm_f(gem_path) if gem_path
  end

  def test_includes_so_files_in_platform_gem
    spec = create_installed_gem_with_extension

    builder = Prebake::PlatformGemBuilder.new(spec)
    gem_path = builder.build

    package = Gem::Package.new(gem_path)
    ext = RUBY_PLATFORM.include?("darwin") ? "bundle" : "so"
    binary_files = package.spec.files.select { |f| f.end_with?(".#{ext}") }
    refute_empty binary_files, "Platform gem should include compiled binary files"
  ensure
    FileUtils.rm_f(gem_path) if gem_path
  end

  def test_computes_sha256_checksum
    spec = create_installed_gem_with_extension

    builder = Prebake::PlatformGemBuilder.new(spec)
    gem_path = builder.build
    checksum = builder.checksum

    assert_match(/\A[a-f0-9]{64}\z/, checksum)
    assert_equal Digest::SHA256.file(gem_path).hexdigest, checksum
  ensure
    FileUtils.rm_f(gem_path) if gem_path
  end

  def test_build_does_not_change_callers_working_directory
    original_dir = Dir.pwd
    spec = create_installed_gem_with_extension

    builder = Prebake::PlatformGemBuilder.new(spec)
    gem_path = builder.build

    assert_equal original_dir, Dir.pwd,
                 "build should not change the caller's working directory"
  ensure
    FileUtils.rm_f(gem_path) if gem_path
  end

  def test_collects_extension_platform_abi_binaries_normalized_to_root
    spec = create_installed_gem_with_extension

    # Remove root-level binary, simulate Ruby 4.0 layout where make install
    # places the .so under extension/<platform>/<abi>/ inside extension_dir
    ext = RUBY_PLATFORM.include?("darwin") ? "bundle" : "so"
    FileUtils.rm_f(File.join(spec.extension_dir, "testgem.#{ext}"))
    nested = File.join(spec.extension_dir, "extension", "x86_64-linux", "4.0.0")
    FileUtils.mkdir_p(nested)
    File.write(File.join(nested, "testgem.#{ext}"), "RUBY40_BINARY")

    builder = Prebake::PlatformGemBuilder.new(spec)
    gem_path = builder.build

    package = Gem::Package.new(gem_path)
    binary_files = package.spec.files.select { |f| f.end_with?(".#{ext}") }
    assert_equal 1, binary_files.size, "Should include extension/<platform>/<abi>/ binary normalized to root"
    assert_equal "testgem.#{ext}", binary_files.first
  ensure
    FileUtils.rm_f(gem_path) if gem_path
  end

  def test_prefers_root_level_binary_over_nested_extension_path
    spec = create_installed_gem_with_extension

    # Both root-level and nested binaries exist — root should win
    ext = RUBY_PLATFORM.include?("darwin") ? "bundle" : "so"
    nested = File.join(spec.extension_dir, "extension", "x86_64-linux", "4.0.0")
    FileUtils.mkdir_p(nested)
    File.write(File.join(nested, "testgem.#{ext}"), "STALE_ARTIFACT")

    builder = Prebake::PlatformGemBuilder.new(spec)
    gem_path = builder.build

    package = Gem::Package.new(gem_path)
    binary_files = package.spec.files.select { |f| f.end_with?(".#{ext}") }
    assert_equal 1, binary_files.size, "Should only include root-level binary when both exist"
    assert_equal "testgem.#{ext}", binary_files.first
  ensure
    FileUtils.rm_f(gem_path) if gem_path
  end

  private

  def create_installed_gem_with_extension
    gem_dir = File.join(@tmpdir, "testgem-1.0.0")
    extension_dir = File.join(@tmpdir, "extensions", "testgem-1.0.0")
    FileUtils.mkdir_p(File.join(gem_dir, "lib/testgem"))
    FileUtils.mkdir_p(File.join(gem_dir, "ext/testgem"))
    FileUtils.mkdir_p(extension_dir)

    File.write(File.join(gem_dir, "lib/testgem.rb"), "# test")

    # Simulate a compiled .so/.bundle in extension_dir (where make install puts it)
    ext = RUBY_PLATFORM.include?("darwin") ? "bundle" : "so"
    File.write(File.join(extension_dir, "testgem.#{ext}"), "FAKE_BINARY")

    spec = Gem::Specification.new do |s|
      s.name = "testgem"
      s.version = "1.0.0"
      s.platform = "ruby"
      s.authors = ["Test"]
      s.summary = "Test gem"
      s.homepage = "https://example.com"
      s.license = "MIT"
      s.extensions = ["ext/testgem/extconf.rb"]
      s.files = ["lib/testgem.rb"]
    end

    # Stub gem_dir and extension_dir to point to our temp directories
    spec.define_singleton_method(:gem_dir) { gem_dir }
    spec.define_singleton_method(:full_gem_path) { gem_dir }
    spec.define_singleton_method(:extension_dir) { extension_dir }

    spec
  end
end
