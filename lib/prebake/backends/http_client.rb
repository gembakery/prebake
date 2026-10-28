# frozen_string_literal: true

require "net/http"
require "timeout"

module Prebake
  module Backends
    module HttpClient
      TIMEOUT = 30
      # Net::HTTP's timeouts restart on every read, so a trickling response needs a total cap.
      DEADLINE = 10
      HTTP_METHODS = { get: Net::HTTP::Get, head: Net::HTTP::Head,
                       post: Net::HTTP::Post, put: Net::HTTP::Put,
                       delete: Net::HTTP::Delete }.freeze

      private

      def http_request(method, uri, body: nil)
        # After one failed download the cache is likely struggling, so the rest of the install builds from source.
        raise Error, "Skipped: an earlier request to the cache failed" if @unavailable && !body

        request = build_http_request(method, uri)
        if body
          request["Content-Type"] = "application/octet-stream"
          request.body = body
        end

        # Uploads carry whole gems, so they keep only the per-phase timeouts.
        Timeout.timeout(body ? nil : DEADLINE) do
          Net::HTTP.start(uri.host, uri.port,
                          use_ssl: uri.scheme == "https",
                          open_timeout: TIMEOUT,
                          read_timeout: TIMEOUT) do |http|
            http.request(request)
          end
        end
      rescue StandardError
        @unavailable = true unless body
        raise
      end

      def build_http_request(method, uri)
        request = HTTP_METHODS.fetch(method).new(uri)
        apply_auth_header(request)
        request
      end

      def apply_auth_header(request)
        raise NotImplementedError, "#{self.class} must implement apply_auth_header"
      end
    end
  end
end
