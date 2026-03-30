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
    return if Gem::Ext::Builder.ancestors.include?(Prebake::ExtBuilderPatch)

    Gem::Ext::Builder.prepend(Prebake::ExtBuilderPatch)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
    Prebake.reset!
  end

  def make_spec(**overrides)
    spec = mock("spec")
    { extensions: ["ext/test/extconf.rb"], name: "testgem",
      version: Gem::Version.new(overrides.delete(:version) || "1.0.0"),
      extension_dir: @extension_dir, gem_build_complete_path: @build_complete,
      full_gem_path: @gem_dir, raw_require_paths: ["lib"] }
      .merge(overrides).each { |m, v| spec.stubs(m).returns(v) }
    spec
  end

  def cache_key = Prebake::CacheKey.for("testgem", "1.0.0", Prebake::Platform.generalized)

  def fake_gem_path
    path = File.join(@tmpdir, "fake.gem")
    File.write(path, "fake")
    path
  end

  def build(spec) = Gem::Ext::Builder.new(spec, "").build_extensions

  def test_skips_compilation_when_cache_hit_with_valid_checksum
    spec = make_spec
    gem_path = fake_gem_path
    checksum = Digest::SHA256.file(gem_path).hexdigest
    backend = mock("backend")
    backend.expects(:fetch_checksum).with(cache_key).returns(checksum)
    backend.expects(:fetch).with(cache_key).returns(gem_path)
    Prebake.backend = backend
    Prebake::Extractor.expects(:install).with(gem_path, spec).returns(1)
    build(spec)
    assert File.exist?(@build_complete), "gem_build_complete marker should be written"
  end

  def test_deletes_and_triggers_rebuild_when_no_checksum_available
    spec = make_spec
    backend = mock("backend")
    backend.expects(:fetch_checksum).with(cache_key).returns(nil)
    backend.expects(:checksums_supported?).returns(true)
    backend.expects(:delete).with(cache_key)
    backend.expects(:fetch).with(cache_key).returns(nil)
    Prebake.backend = backend
    Prebake::Extractor.expects(:install).never
    assert_raises(Gem::Ext::BuildError) { build(spec) }
  end

  def test_accepts_gem_without_checksum_when_backend_does_not_support_checksums
    spec = make_spec
    gem_path = fake_gem_path
    backend = mock("backend")
    backend.expects(:fetch_checksum).with(cache_key).returns(nil)
    backend.expects(:checksums_supported?).returns(false)
    backend.expects(:delete).never
    backend.expects(:fetch).with(cache_key).returns(gem_path)
    Prebake.backend = backend
    Prebake::Extractor.expects(:install).with(gem_path, spec).returns(1)
    build(spec)
    assert File.exist?(@build_complete), "gem_build_complete marker should be written"
  end

  def test_falls_through_on_cache_miss
    spec = make_spec
    backend = mock("backend")
    backend.stubs(:fetch_checksum).with(cache_key).returns("somechecksum")
    backend.expects(:fetch).with(cache_key).returns(nil)
    Prebake.backend = backend
    assert_raises(Gem::Ext::BuildError) { build(spec) }
  end

  def test_skips_gems_without_extensions
    spec = make_spec(extensions: [])
    backend = mock("backend")
    backend.expects(:fetch).never
    Prebake.backend = backend
    build(spec)
  end

  def test_deletes_cache_and_falls_back_when_no_binaries_in_cached_gem
    spec = make_spec
    gem_path = fake_gem_path
    checksum = Digest::SHA256.file(gem_path).hexdigest
    backend = mock("backend")
    backend.expects(:fetch_checksum).with(cache_key).returns(checksum)
    backend.expects(:fetch).with(cache_key).returns(gem_path)
    backend.expects(:delete).with(cache_key)
    Prebake.backend = backend
    Prebake::Extractor.expects(:install).with(gem_path, spec).returns(0)
    assert_raises(Gem::Ext::BuildError) { build(spec) }
    refute File.exist?(@build_complete), "gem_build_complete marker should not be written"
  end

  def test_falls_through_when_backend_nil
    spec = make_spec
    Prebake.backend = nil
    assert_raises(Gem::Ext::BuildError) { build(spec) }
  end
end
