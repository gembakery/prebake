# frozen_string_literal: true

require "test_helper"
require "prebake/logger"

class LoggerTest < Minitest::Test
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
    captured = nil
    Kernel.stub(:warn, ->(msg) { captured = msg }) do
      Bundler.stub(:respond_to?, false) do
        Prebake::Logger.warn("recursion check")
      end
    end

    assert_equal "  [prebake] WARN: recursion check", captured
  end

  def test_output_delegates_to_bundler_ui_when_available
    fake_ui = mock("bundler_ui")
    fake_ui.expects(:info).with("test message")

    Bundler.stub(:ui, fake_ui) do
      Prebake::Logger.output("test message")
    end
  end
end
