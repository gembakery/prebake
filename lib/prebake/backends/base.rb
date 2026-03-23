# frozen_string_literal: true

module Prebake
  module Backends
    class Base
      def fetch(cache_key)
        raise NotImplementedError, "#{self.class}#fetch not implemented"
      end

      def fetch_checksum(cache_key)
        raise NotImplementedError, "#{self.class}#fetch_checksum not implemented"
      end

      def push(gem_path, cache_key, checksum)
        raise NotImplementedError, "#{self.class}#push not implemented"
      end

      def exists?(cache_key)
        raise NotImplementedError, "#{self.class}#exists? not implemented"
      end

      def delete(cache_key)
        raise NotImplementedError, "#{self.class}#delete not implemented"
      end

      def checksums_supported?
        true
      end
    end
  end
end
