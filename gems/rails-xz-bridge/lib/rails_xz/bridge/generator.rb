# frozen_string_literal: true

module RailsXz
  module Bridge
    # Build-time generator: emits a Ruby binding module from an .xzint interface
    # (or the header produced by `xz build --shared`).
    #
    #   Generator.new("liborder.xzint", lib: "liborder.so").generate
    #   # => String of Ruby source for Xz::Bindings::Order
    #
    # The first implementation lands in Phase 1. See docs/01-bridge.md.
    class Generator
      def initialize(interface_path, lib: nil, module_name: nil)
        @interface_path = interface_path
        @lib = lib
        @module_name = module_name
      end

      def generate
        raise NotImplementedError,
              "rails-xz-bridge Generator lands in Phase 1 (docs/05-roadmap.md)"
      end
    end
  end
end