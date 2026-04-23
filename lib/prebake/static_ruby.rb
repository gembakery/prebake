# frozen_string_literal: true

module Prebake
  # Detection and configuration for static Ruby builds (e.g. Paketo MRI buildpack),
  # where libruby.so is absent and native extensions dynamically linked against it
  # would crash at load time.
  module StaticRuby
    # Gems whose native extensions are entirely optional — the gem runs correctly in pure Ruby
    # mode when the extension can't be loaded. Prebake skips the extension for these gems
    # instead of installing a broken .so. Extend via PREBAKE_OPTIONAL_NATIVE_EXTENSIONS=gem1,gem2.
    # Intentionally empty: bootsnap 1.18+ requires its native extension unconditionally;
    # skipping the build produces a broken install.
    OPTIONAL_NATIVE_EXTENSIONS_DEFAULT = %w[].freeze

    class << self
      def optional_native_extensions
        @optional_native_extensions ||= begin
          extra = ENV.fetch("PREBAKE_OPTIONAL_NATIVE_EXTENSIONS", "")
                     .split(",").map(&:strip).reject(&:empty?)
          (OPTIONAL_NATIVE_EXTENSIONS_DEFAULT + extra).uniq
        end
      end

      def optional_native_extension?(gem_name)
        optional_native_extensions.include?(gem_name)
      end

      def libruby_available?
        return @libruby_available if defined?(@libruby_available)

        libruby_so = RbConfig::CONFIG["LIBRUBY_SO"]
        @libruby_available = !libruby_so.nil? && !libruby_so.empty? &&
                             File.exist?(File.join(RbConfig::CONFIG["libdir"], libruby_so))
      end

      def reset!
        remove_instance_variable(:@optional_native_extensions) if defined?(@optional_native_extensions)
        remove_instance_variable(:@libruby_available) if defined?(@libruby_available)
      end
    end
  end
end
