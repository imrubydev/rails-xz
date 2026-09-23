# frozen_string_literal: true

module RailsXz
  module Bridge
    # Opaque wrapper around a C `void*` (the `Ptr` type). A handle carries an
    # address and is frozen, so it never behaves like a plain value and a bare
    # Integer cannot stand in for a pointer (docs/01-bridge.md section 4.4).
    #
    # Lifetime and `transfer` semantics are a later slice; this object makes the
    # pointer's identity explicit and rejects an implicit conversion in either
    # direction.
    class Handle
      def initialize(address)
        @address = address.to_i
        freeze
      end

      def to_i
        @address
      end

      def null?
        @address.zero?
      end

      def ==(other)
        other.is_a?(Handle) && other.to_i == @address
      end
      alias eql? ==

      def hash
        @address.hash
      end

      def inspect
        "#<#{self.class} address=0x#{@address.to_s(16)}>"
      end
    end
  end
end
