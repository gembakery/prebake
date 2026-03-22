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
      files: { "lib/testgem/testgem.so" => "fake-shared-object" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "lib/testgem/testgem.so")
    assert File.exist?(extracted), "Expected #{extracted} to exist"
    assert_equal "fake-shared-object", File.read(extracted)
  end

  def test_extracts_bundle_files_to_extension_dir
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: { "lib/testgem/testgem.bundle" => "fake-bundle" }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    extracted = File.join(@extension_dir, "lib/testgem/testgem.bundle")
    assert File.exist?(extracted), "Expected #{extracted} to exist"
  end

  def test_skips_non_binary_files
    gem_path = build_fake_platform_gem(
      "testgem", "1.0.0",
      files: {
        "lib/testgem/testgem.so" => "binary",
        "lib/testgem/version.rb" => "VERSION = '1.0.0'"
      }
    )

    spec = mock("spec")
    spec.stubs(:extension_dir).returns(@extension_dir)

    Prebake::Extractor.install(gem_path, spec)

    assert File.exist?(File.join(@extension_dir, "lib/testgem/testgem.so"))
    refute File.exist?(File.join(@extension_dir, "lib/testgem/version.rb"))
  end

  private

  def build_fake_platform_gem(name, version, files:)
    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.platform = Gem::Platform.local
      s.authors = ["Test"]
      s.summary = "Test gem"
      s.homepage = "https://example.com"
      s.license = "MIT"
      s.files = files.keys
    end

    gem_dir = File.join(@tmpdir, "build")
    FileUtils.mkdir_p(gem_dir)

    files.each do |path, content|
      full_path = File.join(gem_dir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end

    gem_file = nil
    Dir.chdir(gem_dir) do
      gem_file = Gem::Package.build(spec)
    end

    File.join(gem_dir, gem_file)
  end
end
