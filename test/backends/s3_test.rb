# frozen_string_literal: true

require "test_helper"

STUBS_DIR = File.expand_path("../stubs", __dir__)
$LOAD_PATH.unshift(STUBS_DIR)
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

  def test_initialize_raises_without_aws_sdk
    $LOAD_PATH.delete(STUBS_DIR)
    $LOADED_FEATURES.reject! { |f| f.include?("aws-sdk-s3") }

    error = assert_raises(Prebake::Error) do
      Prebake::Backends::S3.new(bucket: "b", region: "us-east-1", prefix: "p")
    end
    assert_equal "aws-sdk-s3 gem is required for S3 backend", error.message
  ensure
    $LOAD_PATH.unshift(STUBS_DIR) unless $LOAD_PATH.include?(STUBS_DIR)
  end
end
