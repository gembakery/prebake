# frozen_string_literal: true

require_relative "elf_inspector"
require_relative "glibc"
require_relative "logger"

module Prebake
  # Host-side portability guards for cached gems: ensures the cached binary
  # will actually load on this host (glibc version + libruby.so presence).
  module PortabilityGuard
    module_function

    def portable_for_host?(gem_path, spec_name:)
      return true unless Glibc.linux?
      return true if Prebake.skip_portability_check?

      glibc_ok?(gem_path, spec_name:) && libruby_ok?(gem_path, spec_name:)
    end

    def glibc_ok?(gem_path, spec_name:)
      required = ElfInspector.required_glibc_for_gem(gem_path)
      return true if Glibc.compatible?(required)

      Logger.warn "Cached #{spec_name} requires glibc #{required}, " \
                  "host has #{Glibc.detected_version || 'unknown'}; falling back to source build"
      false
    end

    def libruby_ok?(gem_path, spec_name:)
      return true if Prebake.libruby_available?
      return true unless ElfInspector.libruby_needed_for_gem?(gem_path)

      Logger.warn "Cached #{spec_name} requires libruby.so (dynamic Ruby build) " \
                  "but this host has a static Ruby; falling back to source build"
      false
    end
  end
end
