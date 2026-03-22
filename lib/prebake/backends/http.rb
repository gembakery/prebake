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

        return if @url.start_with?("https://") || ENV.fetch("PREBAKE_ALLOW_INSECURE", "false") == "true"
        return unless @url.start_with?("http://")

        Logger.warn(
          "Using insecure HTTP connection to #{@url}. " \
          "Set PREBAKE_ALLOW_INSECURE=true to suppress this warning."
        )
      end

      def fetch(cache_key)
        uri = URI("#{@url}/gems/#{cache_key}")
        response = http_request(:get, uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        path = File.join(Dir.tmpdir, "prebake-#{SecureRandom.hex(16)}.gem")
        File.binwrite(path, response.body)
        path
      rescue StandardError => e
        Logger.debug "Fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def fetch_checksum(cache_key)
        uri = URI("#{@url}/gems/#{cache_key}.sha256")
        response = http_request(:get, uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        response.body.strip
      rescue StandardError => e
        Logger.debug "Checksum fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def push(gem_path, cache_key, checksum)
        gem_uri = URI("#{@url}/gems/#{cache_key}")
        gem_response = http_request(:put, gem_uri, body: File.binread(gem_path))

        unless gem_response.is_a?(Net::HTTPSuccess)
          Logger.warn "Failed to push #{cache_key}: #{gem_response.code}"
          return false
        end

        # Checksum is a secondary artifact - log failure but don't fail the push.
        # The gem itself was pushed successfully; missing checksums can be backfilled.
        checksum_uri = URI("#{@url}/gems/#{cache_key}.sha256")
        checksum_response = http_request(:put, checksum_uri, body: checksum)

        unless checksum_response.is_a?(Net::HTTPSuccess)
          Logger.warn "Checksum push failed for #{cache_key}: #{checksum_response.code}"
        end

        Logger.info "Pushed #{cache_key}"
        true
      rescue StandardError => e
        Logger.warn "Push failed for #{cache_key}: #{e.message}"
        false
      end

      def exists?(cache_key)
        uri = URI("#{@url}/gems/#{cache_key}")
        response = http_request(:head, uri)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      private

      def apply_auth_header(request)
        request["Authorization"] = "Bearer #{@token}" if @token
      end
    end
  end
end
