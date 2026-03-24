# frozen_string_literal: true

require_relative "../logger"

module Prebake
  module Backends
    class Base
      def fetch(cache_key)
        raise NotImplementedError, "#{self.class}#fetch not implemented"
      end

      def fetch_checksum(_cache_key)
        nil
      end

      def push(gem_path, cache_key, checksum)
        raise NotImplementedError, "#{self.class}#push not implemented"
      end

      def exists?(_cache_key)
        false
      end

      def delete(_cache_key)
        false
      end

      def checksums_supported?
        true
      end

      protected

      def warn_if_insecure_http(url)
        return if url.start_with?("https://")
        return if ENV.fetch("PREBAKE_ALLOW_INSECURE", "false") == "true"
        return unless url.start_with?("http://")
        return if darwin_with_default_host?(url)

        Logger.warn(
          "Using insecure HTTP connection to #{url}. " \
          "Set PREBAKE_ALLOW_INSECURE=true to suppress this warning."
        )
      end

      private

      def darwin_with_default_host?(url)
        RUBY_PLATFORM.include?("darwin") &&
          Prebake.backend_type == "http" &&
          url.chomp("/") == Prebake::DEFAULT_HTTP_URL
      end
    end
  end
end
