# frozen_string_literal: true

require "uri"
require "securerandom"
require_relative "base"
require_relative "http_client"
require_relative "../logger"

module Prebake
  module Backends
    class Gemstash < Base
      include HttpClient

      # Gemstash serves private gems at /private/gems/{name}-{version}-{platform}.gem
      # based on the gem's internal metadata. Our cache key includes the Ruby ABI
      # (e.g., puma-6.4.3-arm64-darwin-ruby4.0.gem) which Gemstash doesn't know about.
      #
      # To make this work, we encode the Ruby ABI into the gem version when building:
      # puma version 6.4.3 becomes 6.4.3.pre.ruby40 in the Gemstash-stored gem.
      # Gemstash then serves it at /private/gems/puma-6.4.3.pre.ruby40-arm64-darwin.gem
      #
      # The push endpoint is POST /api/v1/gems (standard RubyGems push).
      # The fetch endpoint is GET /private/gems/{gem_filename}.
      # Auth is via Authorization header with the Gemstash API key.

      def initialize(url:, key: nil)
        @url = url.chomp("/")
        @key = key

        return if @url.start_with?("https://") || ENV.fetch("PREBAKE_ALLOW_INSECURE", "false") == "true"
        return unless @url.start_with?("http://")

        Logger.warn(
          "Using insecure HTTP connection to #{@url}. " \
          "Set PREBAKE_ALLOW_INSECURE=true to suppress this warning."
        )
      end

      def fetch(cache_key)
        gem_filename = gemstash_filename(cache_key)
        uri = URI("#{@url}/private/gems/#{gem_filename}")
        response = http_request(:get, uri)
        return nil unless response.is_a?(Net::HTTPSuccess)

        path = File.join(Dir.tmpdir, "prebake-#{SecureRandom.hex(16)}.gem")
        File.binwrite(path, response.body)
        path
      rescue StandardError => e
        Logger.debug "Fetch failed for #{cache_key}: #{e.message}"
        nil
      end

      def fetch_checksum(_cache_key)
        # Gemstash doesn't store arbitrary files alongside gems.
        # Checksum verification is skipped for Gemstash backend.
        nil
      end

      def checksums_supported?
        false
      end

      def delete(_cache_key)
        false
      end

      def push(gem_path, cache_key, _checksum)
        uri = URI("#{@url}/private/api/v1/gems")
        gem_content = File.binread(gem_path)
        response = http_request(:post, uri, body: gem_content)

        case response
        when Net::HTTPSuccess, Net::HTTPConflict
          Logger.info "Pushed #{cache_key} to Gemstash"
          true
        else
          Logger.warn "Failed to push #{cache_key}: #{response.code} #{response.message}"
          false
        end
      rescue StandardError => e
        Logger.warn "Push failed for #{cache_key}: #{e.message}"
        false
      end

      def exists?(cache_key)
        gem_filename = gemstash_filename(cache_key)
        uri = URI("#{@url}/private/gems/#{gem_filename}")
        response = http_request(:head, uri)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      private

      def apply_auth_header(request)
        request["Authorization"] = @key if @key
      end

      def gemstash_filename(cache_key)
        cache_key.sub(/-ruby\d+\.\d+(\.gem)/, '\1')
      end
    end
  end
end
