# frozen_string_literal: true

require "test_helper"
require "prebake/cache_key"

class CacheKeyTest < Minitest::Test
  def test_generates_key_with_name_version_platform_and_abi
    key = Prebake::CacheKey.for("puma", "6.4.3", "arm64-darwin")
    assert_equal "puma-6.4.3-arm64-darwin-ruby#{Prebake::RUBY_ABI_VERSION}.gem", key
  end

  def test_uses_major_minor_only_not_patch
    key = Prebake::CacheKey.for("bootsnap", "1.18.4", "x86_64-linux")
    # Should be ruby4.0, not ruby4.0.0 or ruby4.0.1
    assert_match(/ruby\d+\.\d+\.gem\z/, key)
    refute_match(/ruby\d+\.\d+\.\d+\.gem\z/, key)
  end

  def test_checksum_key_appends_sha256
    key = Prebake::CacheKey.checksum_for("puma", "6.4.3", "arm64-darwin")
    assert_equal "puma-6.4.3-arm64-darwin-ruby#{Prebake::RUBY_ABI_VERSION}.gem.sha256", key
  end
end
