# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "prebake"
  spec.version       = "0.2.7"
  spec.authors       = ["Thejus Paul"]
  spec.email         = ["thejuspaul@pm.me"]

  spec.summary       = "Stop compiling. Start installing. Prebake your native gems."
  spec.description   = "Prebake speeds up bundle install by skipping native gem compilation. " \
                       "It fetches precompiled binaries for gems like puma, nokogiri, pg, grpc, " \
                       "and bootsnap from a shared cache instead of compiling C extensions from source. " \
                       "Drop-in Bundler plugin - one line in your Gemfile, no other changes needed. " \
                       "Works out of the box with the hosted cache at gems.prebake.in, " \
                       "or self-host with S3-compatible storage (AWS S3, Cloudflare R2, Backblaze B2, MinIO) " \
                       "or Gemstash. " \
                       "Works with Ruby 3.2+ and Ruby 4.0 on any platform."
  spec.homepage      = "https://github.com/gembakery/prebake"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files         = ["plugins.rb"] + Dir.glob("lib/**/*.rb")
  spec.require_paths = ["lib"]
end
