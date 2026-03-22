# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "minitest/reporters"
require "mocha/minitest"
require "webmock/minitest"

Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require "prebake"
