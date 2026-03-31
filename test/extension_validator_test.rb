# frozen_string_literal: true

require "test_helper"
require "prebake/extension_validator"
require "fileutils"

class ExtensionValidatorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @extension_dir = File.join(@tmpdir, "extensions", "testgem-1.0.0")
    FileUtils.mkdir_p(@extension_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_skips_without_marker
    # Place a nested binary that would normally be fixed
    nested_dir = File.join(@extension_dir, "extension", "x86_64-linux", "4.0.0")
    FileUtils.mkdir_p(nested_dir)
    File.write(File.join(nested_dir, "foo.so"), "binary-content")

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::ExtensionValidator.validate(spec)

    refute File.exist?(File.join(@extension_dir, "foo.so")),
      "Should not copy binaries when .prebake marker is absent"
  end

  def test_skips_correct_layout
    FileUtils.touch(File.join(@extension_dir, ".prebake"))
    File.write(File.join(@extension_dir, "foo.so"), "binary-content")

    # Also place a nested binary to prove it's not touched
    nested_dir = File.join(@extension_dir, "extension", "x86_64-linux", "4.0.0")
    FileUtils.mkdir_p(nested_dir)
    File.write(File.join(nested_dir, "bar.so"), "nested-content")

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::ExtensionValidator.validate(spec)

    refute File.exist?(File.join(@extension_dir, "bar.so")),
      "Should not copy nested binaries when root-level binaries already exist"
  end

  def test_fixes_extension_pattern
    FileUtils.touch(File.join(@extension_dir, ".prebake"))

    nested_dir = File.join(@extension_dir, "extension", "x86_64-linux", "4.0.0")
    FileUtils.mkdir_p(nested_dir)
    File.write(File.join(nested_dir, "foo.so"), "binary-content")

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::ExtensionValidator.validate(spec)

    dest = File.join(@extension_dir, "foo.so")
    assert File.exist?(dest), "Expected foo.so to be copied to extension_dir root"
    assert_equal "binary-content", File.read(dest)
  end

  def test_fixes_lib_pattern
    FileUtils.touch(File.join(@extension_dir, ".prebake"))

    lib_dir = File.join(@extension_dir, "lib")
    FileUtils.mkdir_p(lib_dir)
    File.write(File.join(lib_dir, "bar.so"), "lib-binary")

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::ExtensionValidator.validate(spec)

    dest = File.join(@extension_dir, "bar.so")
    assert File.exist?(dest), "Expected bar.so to be copied to extension_dir root"
    assert_equal "lib-binary", File.read(dest)
  end
end
