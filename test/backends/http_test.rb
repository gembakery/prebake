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

  CHECKSUM = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
  OTHER_CHECKSUM = "60303ae22b998861bce3b28f33eec1be758a213c86c93c076dbe9f558c11c752"

  def test_fetch_with_checksum_takes_the_checksum_from_the_gem_response
    stub_gem(headers: { "X-Prebake-Sha256" => CHECKSUM })
    stub_checksum_file(OTHER_CHECKSUM)

    path, checksum = @backend.fetch_with_checksum(@cache_key)
    assert_equal "gem-data", File.read(path)
    assert_equal CHECKSUM, checksum
    assert_not_requested :get, "https://prebake.internal/gems/#{@cache_key}.sha256"
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_fetch_with_checksum_falls_back_to_the_checksum_file_without_the_header
    stub_gem
    stub_checksum_file("#{CHECKSUM}\n")

    path, checksum = @backend.fetch_with_checksum(@cache_key)
    assert_equal CHECKSUM, checksum
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_fetch_with_checksum_ignores_a_malformed_header
    stub_gem(headers: { "X-Prebake-Sha256" => "not-a-checksum" })
    stub_checksum_file(CHECKSUM)

    path, checksum = @backend.fetch_with_checksum(@cache_key)
    assert_equal CHECKSUM, checksum
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_fetch_with_checksum_skips_the_checksum_on_404
    stub_request(:get, "https://prebake.internal/gems/#{@cache_key}").to_return(status: 404)

    assert_equal [nil, nil], @backend.fetch_with_checksum(@cache_key)
    assert_not_requested :get, "https://prebake.internal/gems/#{@cache_key}.sha256"
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

  def test_fetch_gives_up_when_the_download_outlasts_the_deadline
    slow_body = lambda do |_request|
      sleep 2
      "gem-data"
    end
    stub_request(:get, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 200, body: slow_body)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = with_deadline(0.2) { @backend.fetch(@cache_key) }

    assert_nil result
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1
  end

  def test_push_is_exempt_from_the_deadline
    slow_ack = lambda do |_request|
      sleep 0.5
      ""
    end
    stub_request(:put, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 201, body: slow_ack)
    stub_request(:put, "https://prebake.internal/gems/#{@cache_key}.sha256")
      .to_return(status: 201)

    Tempfile.create(["test", ".gem"]) do |f|
      f.write("gem-content")
      f.flush
      assert(with_deadline(0.1) { @backend.push(f.path, @cache_key, "abc123") })
    end
  end

  private

  def stub_gem(headers: {})
    stub_request(:get, "https://prebake.internal/gems/#{@cache_key}")
      .to_return(status: 200, body: "gem-data", headers:)
  end

  def with_deadline(seconds)
    client = Prebake::Backends::HttpClient
    original = client::DEADLINE
    client.send(:remove_const, :DEADLINE)
    client.const_set(:DEADLINE, seconds)
    yield
  ensure
    client.send(:remove_const, :DEADLINE)
    client.const_set(:DEADLINE, original)
  end

  def stub_checksum_file(body)
    stub_request(:get, "https://prebake.internal/gems/#{@cache_key}.sha256")
      .to_return(status: 200, body:)
  end
end
