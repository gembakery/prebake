# frozen_string_literal: true

require "fileutils"
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

      def fetch_with_checksum(cache_key)
        path = fetch(cache_key)
        [path, path && fetch_checksum(cache_key)]
      rescue StandardError
        FileUtils.rm_f(path) if path
        raise
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

        Logger.warn(
          "Using insecure HTTP connection to #{url}. " \
          "Set PREBAKE_ALLOW_INSECURE=true to suppress this warning."
        )
      end
    end
  end
end
