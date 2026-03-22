# frozen_string_literal: true

require "test_helper"
require "rubygems/ext"
require "prebake/ext_builder_patch"
require "prebake/cache_key"
require "prebake/platform"

class ExtBuilderPatchTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @extension_dir = File.join(@tmpdir, "extensions")
    @build_complete = File.join(@tmpdir, "gem.build_complete")
    @gem_dir = File.join(@tmpdir, "gem_dir")
    FileUtils.mkdir_p(@extension_dir)
    FileUtils.mkdir_p(@gem_dir)

    # Ensure patch is applied (idempotent)
    return if Gem::Ext::Builder.ancestors.include?(Prebake::ExtBuilderPatch)

    Gem::Ext::Builder.prepend(Prebake::ExtBuilderPatch)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    Prebake.reset!
  end

  def test_skips_compilation_when_cache_hit
    spec = mock("spec")
    spec.stubs(:extensions).returns(["ext/test/extconf.rb"])
    spec.stubs(:name).returns("testgem")
    spec.stubs(:version).returns(Gem::Version.new("1.0.0"))
    spec.stubs(:extension_dir).returns(@extension_dir)
    spec.stubs(:gem_build_complete_path).returns(@build_complete)
    spec.stubs(:full_gem_path).returns(@gem_dir)

    backend = mock("backend")
    gem_path = File.join(@tmpdir, "fake.gem")
    File.write(gem_path, "fake")

    cache_key = Prebake::CacheKey.for("testgem", "1.0.0",
                                      Prebake::Platform.generalized)

    backend.expects(:fetch).with(cache_key).returns(gem_path)
    backend.expects(:fetch_checksum).with(cache_key).returns(nil)

    Prebake.backend = backend
    Prebake::Extractor.expects(:install).with(gem_path, spec)

    builder = Gem::Ext::Builder.new(spec, "")
    builder.build_extensions

    assert File.exist?(@build_complete), "gem_build_complete marker should be written"
  end

  def test_falls_through_on_cache_miss
    spec = mock("spec")
    spec.stubs(:extensions).returns(["ext/test/extconf.rb"])
    spec.stubs(:name).returns("testgem")
    spec.stubs(:version).returns(Gem::Version.new("1.0.0"))
    spec.stubs(:full_gem_path).returns(@gem_dir)
    spec.stubs(:extension_dir).returns(@extension_dir)
    spec.stubs(:gem_build_complete_path).returns(@build_complete)
    spec.stubs(:raw_require_paths).returns(["lib"])

    backend = mock("backend")
    cache_key = Prebake::CacheKey.for("testgem", "1.0.0",
                                      Prebake::Platform.generalized)
    backend.expects(:fetch).with(cache_key).returns(nil)

    Prebake.backend = backend

    # super will be called, which will try to actually build - it will fail
    # because there's no real extension, but the point is it was called
    builder = Gem::Ext::Builder.new(spec, "")
    assert_raises(Gem::Ext::BuildError) { builder.build_extensions }
  end

  def test_skips_gems_without_extensions
    spec = mock("spec")
    spec.stubs(:extensions).returns([])
    spec.stubs(:full_gem_path).returns(@gem_dir)

    backend = mock("backend")
    backend.expects(:fetch).never

    Prebake.backend = backend

    builder = Gem::Ext::Builder.new(spec, "")
    builder.build_extensions
    # No error means it returned early
  end

  def test_falls_through_when_backend_nil
    spec = mock("spec")
    spec.stubs(:extensions).returns(["ext/test/extconf.rb"])
    spec.stubs(:full_gem_path).returns(@gem_dir)
    spec.stubs(:extension_dir).returns(@extension_dir)
    spec.stubs(:gem_build_complete_path).returns(@build_complete)
    spec.stubs(:raw_require_paths).returns(["lib"])

    Prebake.backend = nil

    # super will be called
    builder = Gem::Ext::Builder.new(spec, "")
    assert_raises(Gem::Ext::BuildError) { builder.build_extensions }
  end
end
