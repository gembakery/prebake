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

        require "aws-sdk-s3"
      rescue LoadError
        raise Prebake::Error, "aws-sdk-s3 gem is required for S3 backend"
      end

      def fetch(cache_key)
        response = client.get_object(bucket: @bucket, key: object_key(cache_key))
        path = File.join(Dir.tmpdir, "prebake-#{SecureRandom.hex(16)}.gem")
        File.binwrite(path, response.body.read)
        path
      rescue StandardError => e
        Logger.debug "S3 fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def fetch_checksum(cache_key)
        response = client.get_object(bucket: @bucket, key: checksum_key(cache_key))
        response.body.read.strip
      rescue StandardError => e
        Logger.debug "S3 checksum fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def push(gem_path, cache_key, checksum)
        gem_key = object_key(cache_key)
        File.open(gem_path, "rb") do |file|
          client.put_object(bucket: @bucket, key: gem_key, body: file)
        end

        begin
          client.put_object(bucket: @bucket, key: checksum_key(cache_key), body: checksum)
        rescue StandardError => e
          Logger.warn "S3 checksum push failed for #{cache_key}: #{e.message}, removing gem"
          client.delete_object(bucket: @bucket, key: gem_key)
          return false
        end

        Logger.info "Pushed #{cache_key} to S3"
        true
      rescue StandardError => e
        Logger.warn "S3 push failed for #{cache_key}: #{e.message}"
        false
      end

      def exists?(cache_key)
        client.head_object(bucket: @bucket, key: object_key(cache_key))
        true
      rescue StandardError
        false
      end

      def delete(cache_key)
        client.delete_object(bucket: @bucket, key: object_key(cache_key))
        client.delete_object(bucket: @bucket, key: checksum_key(cache_key))
        Logger.info "Deleted #{cache_key} from S3"
        true
      rescue StandardError => e
        Logger.debug "S3 delete failed for #{cache_key}: #{e.message}"
        false
      end

      private

      def object_key(cache_key)
        "#{@prefix}/#{cache_key}"
      end

      def checksum_key(cache_key)
        "#{object_key(cache_key)}.sha256"
      end

      def client
        @client ||= Aws::S3::Client.new(region: @region)
      end
    end
  end
end
