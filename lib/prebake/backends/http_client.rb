# frozen_string_literal: true

require "net/http"

module Prebake
  module Backends
    module HttpClient
      TIMEOUT = 30
      HTTP_METHODS = { get: Net::HTTP::Get, head: Net::HTTP::Head,
                       post: Net::HTTP::Post, put: Net::HTTP::Put }.freeze

      private

      def http_request(method, uri, body: nil)
        request = build_http_request(method, uri)
        if body
          request["Content-Type"] = "application/octet-stream"
          request.body = body
        end

        Net::HTTP.start(uri.host, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: TIMEOUT,
                        read_timeout: TIMEOUT) do |http|
          http.request(request)
        end
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
