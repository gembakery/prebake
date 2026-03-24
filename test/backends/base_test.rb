# frozen_string_literal: true

require "test_helper"
require "prebake/backends/base"

class BaseBackendTest < Minitest::Test
  def setup
    @base = Prebake::Backends::Base.new
  end

  def test_exists_returns_false_by_default
    refute @base.exists?("any-cache-key")
  end

  def test_delete_returns_false_by_default
    refute @base.delete("any-cache-key")
  end

  def test_fetch_checksum_returns_nil_by_default
    assert_nil @base.fetch_checksum("any-cache-key")
  end

  def test_fetch_raises_not_implemented
    error = assert_raises(NotImplementedError) { @base.fetch("any-cache-key") }
    assert_match(/fetch not implemented/, error.message)
  end

  def test_push_raises_not_implemented
    error = assert_raises(NotImplementedError) { @base.push("/path.gem", "key", "checksum") }
    assert_match(/push not implemented/, error.message)
  end

  def test_checksums_supported_by_default
    assert @base.checksums_supported?
  end

  def test_insecure_http_warning_fires_for_http_url
    Prebake::Logger.expects(:warn).with(regexp_matches(/[Ii]nsecure HTTP/))
    @base.send(:warn_if_insecure_http, "http://example.com")
  end

  def test_no_insecure_warning_for_https_url
    Prebake::Logger.expects(:warn).never
    @base.send(:warn_if_insecure_http, "https://example.com")
  end

  def test_insecure_warning_suppressed_by_env_var
    ENV["PREBAKE_ALLOW_INSECURE"] = "true"
    Prebake::Logger.expects(:warn).never
    @base.send(:warn_if_insecure_http, "http://example.com")
  ensure
    ENV.delete("PREBAKE_ALLOW_INSECURE")
  end

  def test_insecure_warning_only_checks_url_scheme_not_auth_state
    Prebake::Logger.expects(:warn).with(regexp_matches(%r{http://no-auth\.example\.com}))
    @base.send(:warn_if_insecure_http, "http://no-auth.example.com")
  end
end
