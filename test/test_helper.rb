# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "minitest/reporters"
require "mocha/minitest"
require "webmock/minitest"
require "rubygems/package"
require "fileutils"
require "tmpdir"

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require "prebake"

module TestGemBuilder
  @tmpdirs = []

  class << self
    attr_reader :tmpdirs
  end

  def build_test_gem(name: "testgem", version: "1.0.0", files: {})
    build_dir = Dir.mktmpdir("prebake-test-gem")
    TestGemBuilder.tmpdirs << build_dir

    spec = Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.platform = Gem::Platform.local
      s.authors = ["Test"]
      s.summary = "Test gem"
      s.homepage = "https://example.com"
      s.license = "MIT"
      s.files = files.keys
    end

    files.each do |path, content|
      full = File.join(build_dir, path)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, content)
    end

    gem_file = nil
    Dir.chdir(build_dir) { gem_file = Gem::Package.build(spec) }
    File.join(build_dir, gem_file)
  end
end

Minitest::Test.include(TestGemBuilder)

Minitest.after_run do
  TestGemBuilder.tmpdirs.each { |d| FileUtils.rm_rf(d) }
  TestGemBuilder.tmpdirs.clear
end
