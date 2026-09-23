# frozen_string_literal: true

module RailsXz
  module Bridge
    # Shared Ruby-value coercions for the two call backends. Fiddle and ffi
    # disagree on native C types but agree on how a Ruby value is validated and
    # shaped, so those rules live here once (docs/01-bridge.md sections 4, 6.1).
    module Values
      module_function

      def char_code(value, context)
        value = value.to_s
        unless value.length == 1
          raise MarshallError,
                "#{context}: Char expects a one-character String, got #{value.inspect}"
        end

        value.ord
      end

      def char_string(raw)
        raw.is_a?(Integer) ? raw.chr : raw.to_s
      end

      # A `Ptr` is an opaque handle, never a bare number: a stray Integer is
      # rejected so it cannot be passed as an address by accident. `nil` is the
      # one null form (docs/01-bridge.md section 4.4).
      def handle_address(value, context)
        case value
        when nil then 0
        when Handle then value.to_i
        else
          raise MarshallError,
                "#{context}: Ptr expects a RailsXz::Bridge::Handle, got #{value.class}"
        end
      end

      def unsupported(context, symbol)
        "#{context}: marshalling '#{symbol}' is not implemented yet " \
          "(docs/01-bridge.md section 6.2)"
      end
    end
  end
end
