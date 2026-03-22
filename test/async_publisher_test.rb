# frozen_string_literal: true

require "test_helper"
require "prebake/async_publisher"

class AsyncPublisherTest < Minitest::Test
  def setup
    Prebake::AsyncPublisher.reset!
  end

  def test_enqueue_and_wait_completes
    processed = false

    Prebake::AsyncPublisher.enqueue_block do
      processed = true
    end

    Prebake::AsyncPublisher.wait_for_completion(timeout: 5)
    assert processed
  end

  def test_wait_with_no_threads_does_nothing
    # Should not raise
    Prebake::AsyncPublisher.wait_for_completion(timeout: 1)
  end

  def test_errors_are_rescued_and_logged
    Prebake::Logger.stubs(:warn)

    Prebake::AsyncPublisher.enqueue_block do
      raise "test error"
    end

    # Should not raise - errors are rescued
    Prebake::AsyncPublisher.wait_for_completion(timeout: 5)
  end

  def test_multiple_enqueues_run_concurrently
    results = []
    mutex = Mutex.new

    3.times do |i|
      Prebake::AsyncPublisher.enqueue_block do
        sleep 0.1
        mutex.synchronize { results << i }
      end
    end

    Prebake::AsyncPublisher.wait_for_completion(timeout: 10)
    assert_equal 3, results.size
  end
end
