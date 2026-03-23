# frozen_string_literal: true

require "test_helper"
require "prebake/backends/s3"

class S3BackendTest < Minitest::Test
  def setup
    @backend = Prebake::Backends::S3.new(
      bucket: "test-bucket",
      region: "us-east-1",
      prefix: "prebake"
    )
    @cache_key = "puma-6.4.3-arm64-darwin-ruby4.0.gem"
  end

  def test_object_key_includes_prefix_and_cache_key
    assert_equal "prebake/puma-6.4.3-arm64-darwin-ruby4.0.gem",
                 @backend.send(:object_key, @cache_key)
  end

  def test_fetch_returns_nil_when_sdk_not_available
    @backend.stub(:sdk_available?, false) do
      assert_nil @backend.fetch(@cache_key)
    end
  end

  def test_exists_returns_false_when_sdk_not_available
    @backend.stub(:sdk_available?, false) do
      refute @backend.exists?(@cache_key)
    end
  end

  def test_delete_returns_false_when_sdk_not_available
    @backend.stub(:sdk_available?, false) do
      refute @backend.delete(@cache_key)
    end
  end
end
