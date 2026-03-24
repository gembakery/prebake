# frozen_string_literal: true

require "test_helper"
require "prebake/logger"

class LoggerTest < Minitest::Test
  MANAGED_ENV_KEYS = %w[PREBAKE_HTTP_URL PREBAKE_BACKEND PREBAKE_LOG_LEVEL].freeze

  def test_output_uses_kernel_warn_when_bundler_ui_unavailable
    # Logger.output must call Kernel.warn (not bare warn) to avoid
    # infinite recursion: self.warn -> output -> warn -> output -> ...
    captured = nil
    Kernel.stub(:warn, ->(msg) { captured = msg }) do
      Bundler.stub(:respond_to?, false) do
        Prebake::Logger.output("hello from fallback")
      end
    end

    assert_equal "hello from fallback", captured
  end

  def test_warn_does_not_stack_overflow_without_bundler_ui
    result = capture_log_output(:warn, "recursion check", env: { "PREBAKE_HTTP_URL" => "https://custom.example.com" })
    assert_equal "  [prebake] WARN: recursion check", result
  end

  def test_warn_suppressed_on_darwin_with_default_host
    skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")

    assert_nil capture_log_output(:warn, "should be suppressed")
  end

  def test_warn_not_suppressed_on_darwin_with_custom_url
    skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")

    result = capture_log_output(:warn, "should not be suppressed",
                                env: { "PREBAKE_HTTP_URL" => "https://custom.example.com" })
    assert_equal "  [prebake] WARN: should not be suppressed", result
  end

  def test_warn_suppressed_on_darwin_with_trailing_slash_url
    skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")

    assert_nil capture_log_output(:warn, "trailing slash check",
                                  env: { "PREBAKE_HTTP_URL" => "#{Prebake::DEFAULT_HTTP_URL}/" })
  end

  def test_warn_not_suppressed_on_darwin_with_non_http_backend
    skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")

    result = capture_log_output(:warn, "gemstash warning", env: { "PREBAKE_BACKEND" => "gemstash" })
    assert_equal "  [prebake] WARN: gemstash warning", result
  end

  def test_warn_fires_on_linux_regardless_of_backend_config
    skip "linux-only test" if RUBY_PLATFORM.include?("darwin")

    result = capture_log_output(:warn, "linux warning")
    assert_equal "  [prebake] WARN: linux warning", result
  end

  def test_debug_unaffected_by_darwin_suppression
    skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")

    result = capture_log_output(:debug, "debug msg", env: { "PREBAKE_LOG_LEVEL" => "debug" })
    assert_equal "  [prebake] debug msg", result
  end

  def test_info_unaffected_by_darwin_suppression
    skip "darwin-only test" unless RUBY_PLATFORM.include?("darwin")

    result = capture_log_output(:info, "info msg", env: { "PREBAKE_LOG_LEVEL" => "info" })
    assert_equal "  [prebake] info msg", result
  end

  def test_output_delegates_to_bundler_ui_when_available
    fake_ui = mock("bundler_ui")
    fake_ui.expects(:info).with("test message")

    Bundler.stub(:ui, fake_ui) do
      Prebake::Logger.output("test message")
    end
  end

  private

  def capture_log_output(method, msg, env: {})
    saved = MANAGED_ENV_KEYS.to_h { |k| [k, ENV.fetch(k, nil)] }
    MANAGED_ENV_KEYS.each { |k| ENV.delete(k) }
    env.each { |k, v| ENV[k] = v }
    Prebake::Logger.reset!

    captured = nil
    Kernel.stub(:warn, ->(m) { captured = m }) do
      Bundler.stub(:respond_to?, false) do
        Prebake::Logger.public_send(method, msg)
      end
    end
    captured
  ensure
    Prebake::Logger.reset!
    saved&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
