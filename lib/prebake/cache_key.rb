# frozen_string_literal: true

module Prebake
  module CacheKey
    def self.for(name, version, platform)
      "#{name}-#{version}-#{platform}-ruby#{Prebake::RUBY_ABI_VERSION}.gem"
    end

    def self.checksum_for(name, version, platform)
      "#{self.for(name, version, platform)}.sha256"
    end
  end
end
