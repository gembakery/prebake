# frozen_string_literal: true

require "uri"
require "securerandom"
require_relative "base"
require_relative "http_client"
require_relative "../logger"

module Prebake
  module Backends
    class Http < Base
      include HttpClient

      def initialize(url:, token: nil)
        @url = url.chomp("/")
        @token = token

        warn_if_insecure_http(@url)
      end

      def fetch(cache_key)
        response = http_request(:get, gem_uri(cache_key))
        return nil unless response.is_a?(Net::HTTPSuccess)

        path = File.join(Dir.tmpdir, "prebake-#{SecureRandom.hex(16)}.gem")
        File.binwrite(path, response.body)
        path
      rescue StandardError => e
        Logger.debug "Fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def fetch_checksum(cache_key)
        response = http_request(:get, checksum_uri(cache_key))
        return nil unless response.is_a?(Net::HTTPSuccess)

        response.body.strip
      rescue StandardError => e
        Logger.debug "Checksum fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def push(gem_path, cache_key, checksum)
        gem_response = http_request(:put, gem_uri(cache_key), body: File.binread(gem_path))

        unless gem_response.is_a?(Net::HTTPSuccess)
          Logger.warn "Failed to push #{cache_key}: #{gem_response.code}"
          return false
        end

        checksum_response = http_request(:put, checksum_uri(cache_key), body: checksum)

        unless checksum_response.is_a?(Net::HTTPSuccess)
          Logger.warn "Checksum push failed for #{cache_key}: #{checksum_response.code}, removing gem"
          http_request(:delete, gem_uri(cache_key))
          return false
        end

        Logger.info "Pushed #{cache_key}"
        true
      rescue StandardError => e
        Logger.warn "Push failed for #{cache_key}: #{e.message}"
        false
      end

      def exists?(cache_key)
        response = http_request(:head, gem_uri(cache_key))
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      def delete(cache_key)
        gem_response = http_request(:delete, gem_uri(cache_key))
        http_request(:delete, checksum_uri(cache_key))

        gem_response.is_a?(Net::HTTPSuccess)
      rescue StandardError => e
        Logger.debug "Delete failed for #{cache_key}: #{e.message}"
        false
      end

      private

      def gem_uri(cache_key)
        URI("#{@url}/gems/#{cache_key}")
      end

      def checksum_uri(cache_key)
        URI("#{@url}/gems/#{cache_key}.sha256")
      end

      def apply_auth_header(request)
        request["Authorization"] = "Bearer #{@token}" if @token
      end
    end
  end
end
