# frozen_string_literal: true

require "test_helper"
require "prebake/backends/gemstash"

class GemstashBackendTest < Minitest::Test
  def setup
    ENV["PREBAKE_ALLOW_INSECURE"] = "true"
    @backend = Prebake::Backends::Gemstash.new(
      url: "http://localhost:9292",
      key: "test-api-key"
    )
    @cache_key = "puma-6.4.3-arm64-darwin-ruby4.0.gem"
    # Gemstash strips the -rubyX.Y from the filename
    @gemstash_filename = "puma-6.4.3-arm64-darwin.gem"
  end

  def teardown
    ENV.delete("PREBAKE_ALLOW_INSECURE")
  end

  def test_fetch_strips_abi_from_url
    stub_request(:get, "http://localhost:9292/private/gems/#{@gemstash_filename}")
      .to_return(status: 200, body: "fake-gem-content")

    result = @backend.fetch(@cache_key)
    assert result
    assert File.exist?(result)
    assert_equal "fake-gem-content", File.read(result)
  ensure
    File.delete(result) if result && File.exist?(result)
  end

  def test_fetch_returns_nil_on_404
    stub_request(:get, "http://localhost:9292/private/gems/#{@gemstash_filename}")
      .to_return(status: 404)
    assert_nil @backend.fetch(@cache_key)
  end

  def test_fetch_returns_nil_on_network_error
    stub_request(:get, "http://localhost:9292/private/gems/#{@gemstash_filename}")
      .to_timeout
    assert_nil @backend.fetch(@cache_key)
  end

  def test_fetch_checksum_always_returns_nil
    # Gemstash doesn't support storing arbitrary checksum files
    assert_nil @backend.fetch_checksum(@cache_key)
  end

  def test_push_posts_gem_with_auth_header
    stub_request(:post, "http://localhost:9292/private/api/v1/gems")
      .with(headers: { "Authorization" => "test-api-key" })
      .to_return(status: 200)

    Tempfile.create(["test", ".gem"]) do |f|
      f.write("gem-content")
      f.flush
      assert @backend.push(f.path, @cache_key, "abc123")
    end
  end

  def test_push_returns_true_on_409_conflict
    stub_request(:post, "http://localhost:9292/private/api/v1/gems")
      .to_return(status: 409)

    Tempfile.create(["test", ".gem"]) do |f|
      f.write("gem-content")
      f.flush
      assert @backend.push(f.path, @cache_key, "abc123")
    end
  end

  def test_push_returns_false_on_error
    Prebake::Logger.stubs(:warn)

    stub_request(:post, "http://localhost:9292/private/api/v1/gems")
      .to_return(status: 500)

    Tempfile.create(["test", ".gem"]) do |f|
      f.write("gem-content")
      f.flush
      refute @backend.push(f.path, @cache_key, "abc123")
    end
  end

  def test_exists_strips_abi_from_url
    stub_request(:head, "http://localhost:9292/private/gems/#{@gemstash_filename}")
      .to_return(status: 200)
    assert @backend.exists?(@cache_key)
  end

  def test_exists_returns_false_on_404
    stub_request(:head, "http://localhost:9292/private/gems/#{@gemstash_filename}")
      .to_return(status: 404)
    refute @backend.exists?(@cache_key)
  end

  def test_gemstash_filename_strips_ruby_abi
    # Verify the internal mapping
    assert_equal "puma-6.4.3-arm64-darwin.gem",
                 @backend.send(:gemstash_filename, "puma-6.4.3-arm64-darwin-ruby4.0.gem")
    assert_equal "bootsnap-1.18.4-x86_64-linux.gem",
                 @backend.send(:gemstash_filename, "bootsnap-1.18.4-x86_64-linux-ruby3.3.gem")
  end
end
