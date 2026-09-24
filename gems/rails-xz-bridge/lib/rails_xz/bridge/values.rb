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
      # one null form (docs/01-bridge.md section 4.4). A handle whose ownership
      # already moved is dead and cannot be passed again.
      def handle_address(value, context)
        case value
        when nil then 0
        when Handle
          if value.consumed?
            raise MarshallError, "#{context}: #{value.inspect} was already transferred"
          end

          value.to_i
        else
          raise MarshallError,
                "#{context}: Ptr expects a RailsXz::Bridge::Handle, got #{value.class}"
        end
      end

      # A `transfer` parameter moves ownership to the callee, so the handle is
      # consumed and cannot be passed or released again (docs/01-bridge.md
      # section 4.6).
      def transfer_address(value, context)
        return 0 if value.nil?
        unless value.is_a?(Handle)
          raise MarshallError,
                "#{context}: transfer Ptr expects a RailsXz::Bridge::Handle, " \
                "got #{value.class}"
        end

        value.consume!
        value.to_i
      end

      def unsupported(context, symbol)
        "#{context}: marshalling '#{symbol}' is not implemented yet " \
          "(docs/01-bridge.md section 6.2)"
      end
    end
  end
end
