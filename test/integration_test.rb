# frozen_string_literal: true

require "test_helper"
require "prebake"
require "prebake/platform_gem_builder"
require "prebake/extractor"
require "prebake/cache_key"
require "prebake/platform"
require "fileutils"
require "securerandom"

class IntegrationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("prebake-integration")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_round_trip_build_and_extract
    # 1. Simulate an installed gem with compiled extensions
    gem_dir = File.join(@tmpdir, "fakegem-1.0.0")
    builder_extension_dir = File.join(@tmpdir, "builder_extensions")
    FileUtils.mkdir_p(File.join(gem_dir, "lib/fakegem"))
    FileUtils.mkdir_p(File.join(gem_dir, "ext/fakegem"))
    FileUtils.mkdir_p(builder_extension_dir)

    ext = RUBY_PLATFORM.include?("darwin") ? "bundle" : "so"
    binary_content = "COMPILED_BINARY_CONTENT_#{SecureRandom.hex(8)}"
    # Place compiled binary in extension_dir (where make install puts it)
    File.write(File.join(builder_extension_dir, "fakegem.#{ext}"), binary_content)
    File.write(File.join(gem_dir, "lib/fakegem.rb"), "require 'fakegem/fakegem'")

    spec = Gem::Specification.new do |s|
      s.name = "fakegem"
      s.version = "1.0.0"
      s.platform = "ruby"
      s.authors = ["Test"]
      s.summary = "Test"
      s.homepage = "https://example.com"
      s.license = "MIT"
      s.extensions = ["ext/fakegem/extconf.rb"]
      s.files = ["lib/fakegem.rb"]
    end
    spec.define_singleton_method(:gem_dir) { gem_dir }
    spec.define_singleton_method(:full_gem_path) { gem_dir }
    spec.define_singleton_method(:extension_dir) { builder_extension_dir }

    # 2. Build platform gem
    builder = Prebake::PlatformGemBuilder.new(spec)
    platform_gem_path = builder.build
    checksum = builder.checksum

    assert File.exist?(platform_gem_path)
    assert_match(/\A[a-f0-9]{64}\z/, checksum)

    # 3. Extract into a clean directory (simulating consumer)
    consumer_extension_dir = File.join(@tmpdir, "consumer_extensions")
    FileUtils.mkdir_p(consumer_extension_dir)

    consumer_spec = mock("spec")
    consumer_spec.stubs(:extension_dir).returns(consumer_extension_dir)

    Prebake::Extractor.install(platform_gem_path, consumer_spec)

    # 4. Verify the binary was extracted to the correct flat path
    extracted = File.join(consumer_extension_dir, "fakegem.#{ext}")
    assert File.exist?(extracted), "Expected #{extracted} to exist"
    assert_equal binary_content, File.read(extracted)
  ensure
    FileUtils.rm_f(platform_gem_path) if platform_gem_path
  end

  def test_cache_key_consistency
    key1 = Prebake::CacheKey.for("puma", "6.4.3",
                                 Prebake::Platform.generalized)
    key2 = Prebake::CacheKey.for("puma", "6.4.3",
                                 Prebake::Platform.generalized)

    assert_equal key1, key2, "Cache keys should be deterministic"
  end

  def test_backend_disabled_when_config_missing
    Prebake.reset!

    # With no PREBAKE_GEMSTASH_URL set, backend should be nil
    ENV.delete("PREBAKE_GEMSTASH_URL")
    ENV["PREBAKE_BACKEND"] = "gemstash"

    backend = Prebake.backend
    assert_nil backend, "Backend should be nil when config is missing"

    # Second call should also return nil (not retry)
    backend2 = Prebake.backend
    assert_nil backend2, "Backend should stay nil (no retry)"
  ensure
    Prebake.reset!
    ENV.delete("PREBAKE_BACKEND")
  end
end
