# frozen_string_literal: true

require "test_helper"
require "prebake/platform"

class PlatformTest < Minitest::Test
  def test_normalizes_arm64_darwin_with_version
    assert_equal "arm64-darwin", Prebake::Platform.normalize("arm64-darwin-23")
  end

  def test_normalizes_x86_64_darwin_with_version
    assert_equal "x86_64-darwin", Prebake::Platform.normalize("x86_64-darwin-23")
  end

  def test_normalizes_x86_64_linux_gnu
    assert_equal "x86_64-linux", Prebake::Platform.normalize("x86_64-linux-gnu")
  end

  def test_normalizes_aarch64_linux_gnu
    assert_equal "aarch64-linux", Prebake::Platform.normalize("aarch64-linux-gnu")
  end

  def test_preserves_musl_suffix
    assert_equal "x86_64-linux-musl", Prebake::Platform.normalize("x86_64-linux-musl")
  end

  def test_preserves_aarch64_musl_suffix
    assert_equal "aarch64-linux-musl", Prebake::Platform.normalize("aarch64-linux-musl")
  end

  def test_generalized_returns_normalized_local_platform
    platform = Prebake::Platform.generalized
    refute_match(/-\d+\z/, platform) # no OS version suffix
    refute_empty platform
  end
end
