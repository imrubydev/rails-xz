# frozen_string_literal: true

module RailsXz
  module Bridge
    # Opaque wrapper around a C `void*` (the `Ptr` type). A handle carries an
    # address and is frozen, so it never behaves like a plain value and a bare
    # Integer cannot stand in for a pointer (docs/01-bridge.md section 4.4).
    #
    # A handle from a `transfer` return (`-> transfer Ptr release <symbol>`)
    # owns the pointer: `#release!` calls the named deallocator exactly once.
    # Handing a handle to a `transfer` parameter moves ownership to the callee,
    # so the handle is marked consumed and cannot be reused or released again
    # (docs/01-bridge.md section 4.6).
    class Handle
      def initialize(address, release: nil)
        @address = address.to_i
        @release = release
        @state = { consumed: false }
        freeze
      end

      def to_i
        @address
      end

      def null?
        @address.zero?
      end

      # Whether ownership has moved away (a `transfer` parameter took it, or
      # `#release!` already ran).
      def consumed?
        @state[:consumed]
      end

      # Moves ownership of the pointer to the callee: the handle is dead
      # afterward and must not be passed or released again.
      def consume!
        if consumed?
          raise MarshallError, "#{inspect} was already transferred"
        end

        @state[:consumed] = true
        self
      end

      # Frees the pointer through the transfer return's `release` symbol. A
      # handle without a releaser (a borrowed pointer) cannot be released.
      def release!
        if @release.nil?
          raise MarshallError,
                "#{inspect} is borrowed and has no release symbol; only a " \
                "'transfer' return can be released"
        end
        return nil if null?
        return nil if consumed?

        @state[:consumed] = true
        @release.call(@address)
        nil
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
