# frozen_string_literal: true

require "test_helper"
require "prebake/extractor"
require "rubygems/package"
require "fileutils"

class ExtractorTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @extension_dir = File.join(@tmpdir, "extensions")
    FileUtils.mkdir_p(@extension_dir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_extracts_so_files_to_extension_dir
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "testgem.so" => "fake-shared-object" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "testgem.so")
    assert File.exist?(extracted), "Expected #{extracted} to exist"
    assert_equal "fake-shared-object", File.read(extracted)
  end

  def test_extracts_bundle_files_to_extension_dir
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "testgem.bundle" => "fake-bundle" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "testgem.bundle")
    assert File.exist?(extracted), "Expected #{extracted} to exist"
  end

  def test_skips_non_binary_files
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: {
        "testgem.so" => "binary",
        "lib/testgem/version.rb" => "VERSION = '1.0.0'"
      }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    assert File.exist?(File.join(@extension_dir, "testgem.so"))
    refute File.exist?(File.join(@extension_dir, "lib/testgem/version.rb"))
  end

  def test_strips_ext_prefix_from_legacy_cached_gems
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "ext/testgem/testgem.so" => "legacy-binary" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "testgem.so")
    assert File.exist?(extracted), "Expected legacy ext/ prefix to be stripped"
    assert_equal "legacy-binary", File.read(extracted)
  end

  def test_skips_empty_binary_files
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "testgem.so" => "" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    count = Prebake::Extractor.install(gem_path, spec)

    assert_equal 0, count, "Empty binaries should not be counted"
    refute File.exist?(File.join(@extension_dir, "testgem.so"))
  end

  def test_strips_extension_platform_prefix_from_dirty_cached_gems
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "extension/x86_64-linux/4.0.0/testgem.so" => "platform-artifact" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "testgem.so")
    assert File.exist?(extracted), "Expected extension/<platform>/<ver>/ prefix to be stripped"
    assert_equal "platform-artifact", File.read(extracted)
    refute File.exist?(File.join(@extension_dir, "extension/x86_64-linux/4.0.0/testgem.so"))
  end

  def test_strips_extensions_plural_platform_prefix
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "extensions/x86_64-linux/4.0.0/testgem.so" => "platform-artifact" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "testgem.so")
    assert File.exist?(extracted), "Expected extensions/<platform>/<ver>/ prefix to be stripped"
    assert_equal "platform-artifact", File.read(extracted)
  end

  def test_strips_lib_prefix_from_legacy_cached_gems
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "lib/testgem/testgem.so" => "legacy-binary" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "testgem/testgem.so")
    assert File.exist?(extracted), "Expected lib/ prefix to be stripped"
    assert_equal "legacy-binary", File.read(extracted)
  end

  def test_writes_prebake_marker_on_successful_extraction
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "testgem.so" => "fake-shared-object" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    marker = File.join(@extension_dir, ".prebake")
    assert File.exist?(marker), "Expected .prebake marker to exist after successful extraction"
    assert_equal 0, File.size(marker), "Marker should be empty"
  end

  def test_does_not_write_prebake_marker_on_extraction_failure
    bad_gem = File.join(@tmpdir, "bad.gem")
    File.write(bad_gem, "not a valid gem")

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    assert_raises(StandardError) { Prebake::Extractor.install(bad_gem, spec) }

    marker = File.join(@extension_dir, ".prebake")
    refute File.exist?(marker), "Marker should not exist when extraction raises"
  end

  private

  def build_fake_platform_gem(name, version, files:)
    build_test_gem(name: name, version: version, files: files)
  end
end
