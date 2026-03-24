# frozen_string_literal: true

require "test_helper"
require "prebake/async_publisher"
require "prebake/platform_gem_builder"

class AsyncPublisherTest < Minitest::Test
  def setup
    Prebake::AsyncPublisher.reset!
    @tmpdir = Dir.mktmpdir
    Prebake::Platform.stubs(:generalized).returns("x86_64-linux")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def mock_spec(name, version)
    stub(name:, version: Gem::Version.new(version))
  end

  def temp_gem_path(name = "fake")
    path = File.join(@tmpdir, "#{name}.gem")
    File.write(path, "fake-content")
    path
  end

  def test_enqueue_and_wait_pushes_gem
    spec = mock_spec("testgem", "1.0.0")
    gem_path = temp_gem_path
    pushed = []
    backend = stub(exists?: false, push: -> { pushed << true })
    backend.expects(:push).with(gem_path, anything, "sha256sum")

    builder = stub(build: gem_path, checksum: "sha256sum")
    Prebake::PlatformGemBuilder.stubs(:new).with(spec).returns(builder)

    Prebake::AsyncPublisher.enqueue(spec, backend)
    Prebake::AsyncPublisher.wait_for_completion(timeout: 5)
  end

  def test_wait_with_no_enqueues_does_nothing
    Prebake::AsyncPublisher.wait_for_completion(timeout: 1)
  end

  def test_errors_in_build_are_rescued
    spec = mock_spec("badgem", "0.1.0")
    backend = stub
    backend.stubs(:exists?).raises(StandardError, "boom")
    Prebake::Logger.stubs(:warn)

    Prebake::AsyncPublisher.enqueue(spec, backend)
    Prebake::AsyncPublisher.wait_for_completion(timeout: 5)
  end

  def test_multiple_enqueues_all_processed
    pushed = []
    3.times do |i|
      spec = mock_spec("gem#{i}", "1.0.#{i}")
      gem_path = temp_gem_path("gem#{i}")
      backend = stub(exists?: false)
      backend.stubs(:push).with { pushed << i }

      builder = stub(build: gem_path, checksum: "sha#{i}")
      Prebake::PlatformGemBuilder.stubs(:new).with(spec).returns(builder)

      Prebake::AsyncPublisher.enqueue(spec, backend)
    end

    Prebake::AsyncPublisher.wait_for_completion(timeout: 10)
    assert_equal 3, pushed.size
  end
end
