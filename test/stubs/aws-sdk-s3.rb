# frozen_string_literal: true

module Aws
  module S3
    Client = Struct.new(:region) unless defined?(Client)
  end
end
