# frozen_string_literal: true

module Aws
  module S3
    Client = Struct.new(:region) unless defined?(Client)

    module Errors
      class NoSuchKey < StandardError; end
    end
  end
end
