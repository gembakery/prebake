# frozen_string_literal: true

require "test_helper"
require "prebake/backends/http"

class HttpBackendTest < Minitest::Test
  def setup
    @backend = Prebake::Backends::Http.new(
      url: "https://prebake.internal",
      token: "bearer-secret"
    )
    @cache_key = "puma-6.4.3-arm64-darwin-ruby4.0.gem"
  end

  def test_fetch_downloads_gem_on_200
    stub_request(:get, "https://prebake.internal/gems/#{@cache_key}")
      .with(headers: { "Authorization" => "Bearer bearer-secret" })
      .to_return(status: 200, body: "gem-data")

    result = @backend.fetch(@cache_key)
    assert result
    assert_equal "gem-data", File.read(result)
  ensure
    File.delete(result) if result && File.exist?(result)
  end

  def test_fetch_returns_nil_on_404
    stub_request(:get, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 404)
    assert_nil @backend.fetch(@cache_key)
  end

  def test_push_sends_put_with_gem_body
    stub_request(:put, "https://prebake.internal/gems/#{@cache_key}")
      .with(headers: { "Authorization" => "Bearer bearer-secret" })
      .to_return(status: 201)
    stub_request(:put, "https://prebake.internal/gems/#{@cache_key}.sha256")
      .to_return(status: 201)

    Tempfile.create(["test", ".gem"]) do |f|
      f.write("gem-content")
      f.flush
      assert @backend.push(f.path, @cache_key, "abc123")
    end
  end

  def test_exists_returns_true_on_200
    stub_request(:head, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 200)
    assert @backend.exists?(@cache_key)
  end

  def test_delete_sends_delete_for_gem_and_checksum
    stub_request(:delete, "https://prebake.internal/gems/#{@cache_key}")
      .with(headers: { "Authorization" => "Bearer bearer-secret" })
      .to_return(status: 200)
    stub_request(:delete, "https://prebake.internal/gems/#{@cache_key}.sha256")
      .with(headers: { "Authorization" => "Bearer bearer-secret" })
      .to_return(status: 200)

    assert @backend.delete(@cache_key)
  end

  def test_delete_returns_false_on_gem_404
    stub_request(:delete, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 404)
    stub_request(:delete, "https://prebake.internal/gems/#{@cache_key}.sha256")
      .to_return(status: 404)

    refute @backend.delete(@cache_key)
  end

  def test_warns_on_insecure_http_url
    Prebake::Logger.expects(:warn).with(regexp_matches(/[Ii]nsecure HTTP/))
    Prebake::Backends::Http.new(url: "http://insecure.example.com", token: "secret")
  end

  def test_push_cleans_up_gem_when_checksum_push_fails
    stub_request(:put, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 201)
    stub_request(:put, "https://prebake.internal/gems/#{@cache_key}.sha256")
      .to_return(status: 500)
    stub_request(:delete, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 200)

    Tempfile.create(["test", ".gem"]) do |f|
      f.write("gem-content")
      f.flush
      refute @backend.push(f.path, @cache_key, "abc123")
    end
  end
end
