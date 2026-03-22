# frozen_string_literal: true

require "tempfile"
require "securerandom"
require_relative "base"
require_relative "../logger"

module Prebake
  module Backends
    class S3 < Base
      def initialize(bucket:, region: "us-east-1", prefix: "prebake")
        @bucket = bucket
        @region = region
        @prefix = prefix
      end

      def fetch(cache_key)
        return nil unless sdk_available?

        response = client.get_object(bucket: @bucket, key: object_key(cache_key))
        path = File.join(Dir.tmpdir, "prebake-#{SecureRandom.hex(16)}.gem")
        File.binwrite(path, response.body.read)
        path
      rescue StandardError => e
        Logger.debug "S3 fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def fetch_checksum(cache_key)
        return nil unless sdk_available?

        response = client.get_object(bucket: @bucket, key: "#{object_key(cache_key)}.sha256")
        response.body.read.strip
      rescue StandardError => e
        Logger.debug "S3 checksum fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def push(gem_path, cache_key, checksum)
        return false unless sdk_available?

        File.open(gem_path, "rb") do |file|
          client.put_object(bucket: @bucket, key: object_key(cache_key), body: file)
        end
        client.put_object(bucket: @bucket, key: "#{object_key(cache_key)}.sha256", body: checksum)
        Logger.info "Pushed #{cache_key} to S3"
        true
      rescue StandardError => e
        Logger.warn "S3 push failed for #{cache_key}: #{e.message}"
        false
      end

      def exists?(cache_key)
        return false unless sdk_available?

        client.head_object(bucket: @bucket, key: object_key(cache_key))
        true
      rescue StandardError
        false
      end

      private

      def object_key(cache_key)
        "#{@prefix}/#{cache_key}"
      end

      def sdk_available?
        require "aws-sdk-s3"
        true
      rescue LoadError
        Logger.warn "aws-sdk-s3 not available. Install it to use S3 backend."
        false
      end

      def client
        @client ||= Aws::S3::Client.new(region: @region)
      end
    end
  end
end
