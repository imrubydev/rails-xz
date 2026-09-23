# frozen_string_literal: true

require "ffi"

module RailsXz
  module Bridge
    # Call strategy for signatures that cross a by-value aggregate. Fiddle
    # cannot pass or return a C struct by value, so a signature containing
    # `Str`, `Bytes`, or a `@cstruct` is bound through the ffi gem; scalar- and
    # pointer-only signatures stay on Fiddle (docs/01-bridge.md section 3).
    #
    # The Xz C ABI is authoritative: `Str`/`Bytes` are `{ ptr, len }` structs
    # and a `@cstruct` is a C struct in declaration order. This class maps the
    # generated type symbols to ffi types and moves values across
    # (docs/01-bridge.md sections 4, 6.1).
    class FfiMarshaller
      class XzStr < FFI::Struct
        layout :ptr, :pointer, :len, :size_t
      end

      class XzBytes < FFI::Struct
        layout :ptr, :pointer, :len, :size_t
      end

      PRIMITIVE_TYPES = {
        bool: :bool,
        int: :long_long,
        usize: :ulong_long,
        float: :double,
        char: :char,
        ptr: :pointer,
        unit: :void
      }.freeze

      MUT_PREFIX = "mut_"

      # A typed in/out cell: the native memory the callee writes through, plus
      # the reader that turns it back into a Ruby value after the call.
      Cell = Struct.new(:pointer, :reader) do
        def read
          reader.call
        end
      end

      def initialize(binding, loader)
        @binding = binding
        @loader = loader
        @cstruct_classes = {}
      end

      def call(name, params, returns, args, release_gvl: false)
        function = @loader.ffi_function(
          name.to_s,
          return_type(returns, context: "#{name} return"),
          params.map do |param, symbol|
            argument_type(symbol, context: "#{name} parameter '#{param}'")
          end,
          blocking: release_gvl
        )

        keepalive = []
        cells = {}
        encoded = params.each_with_index.map do |(param, symbol), index|
          context = "#{name} parameter '#{param}'"
          if mut?(symbol)
            cells[param] = build_cell(symbol, args[index], keepalive, context)
            cells[param].pointer
          else
            encode(symbol, args[index], keepalive, context: context)
          end
        end

        value = decode(returns, function.call(*encoded), context: "#{name} return")
        return value if cells.empty?

        [value, cells.transform_values(&:read)]
      end

      private

      def mut?(symbol)
        symbol.to_s.start_with?(MUT_PREFIX)
      end

      def base_symbol(symbol)
        symbol.to_s.delete_prefix(MUT_PREFIX).to_sym
      end

      def return_type(symbol, context:)
        symbol == :unit ? :void : argument_type(symbol, context: context)
      end

      def argument_type(symbol, context:)
        return :pointer if mut?(symbol)

        primitive = PRIMITIVE_TYPES[symbol]
        return primitive if primitive
        return XzStr.by_value if symbol == :str
        return XzBytes.by_value if symbol == :bytes
        return cstruct_class(symbol).by_value if cstruct?(symbol)

        raise MarshallError, Values.unsupported(context, symbol)
      end

      # A struct field nests by value, so it uses the plain class, not
      # `.by_value` (which is only for function arguments and returns).
      def field_type(symbol)
        primitive = PRIMITIVE_TYPES[symbol]
        return primitive if primitive && symbol != :unit
        return XzStr if symbol == :str
        return XzBytes if symbol == :bytes
        return cstruct_class(symbol) if cstruct?(symbol)

        raise MarshallError, Values.unsupported("field", symbol)
      end

      def cstruct?(symbol)
        @binding.declared_cstructs.key?(symbol)
      end

      def cstruct_class(name)
        @cstruct_classes[name] ||= begin
          fields = @binding.declared_cstructs.fetch(name)
          layout = fields.flat_map { |field, symbol| [field, field_type(symbol)] }
          Class.new(FFI::Struct).tap { |klass| klass.layout(*layout) }
        end
      end

      # -- encode (Ruby -> C) --------------------------------------------------

      def encode(symbol, value, keepalive, context:)
        case symbol
        when :bool then value ? true : false
        when :int, :usize then Integer(value)
        when :float then Float(value)
        when :char then Values.char_code(value, context)
        when :ptr then ffi_pointer(value, context)
        when :str then encode_str(value, keepalive, context)
        when :bytes then encode_bytes(value, keepalive, context)
        else
          if cstruct?(symbol)
            encode_cstruct(symbol, value, keepalive, context)
          else
            raise MarshallError, Values.unsupported(context, symbol)
          end
        end
      end

      # ffi rejects a bare Integer for `:pointer`, so an address becomes an
      # FFI::Pointer and null becomes nil.
      def ffi_pointer(value, context)
        address = Values.handle_address(value, context)
        address.zero? ? nil : FFI::Pointer.new(address)
      end

      def encode_str(value, keepalive, context)
        fill_str(XzStr.new, value, keepalive, context)
      end

      def encode_bytes(value, keepalive, context)
        fill_bytes(XzBytes.new, value, keepalive, context)
      end

      # Builds the `Str` pair over `struct`, which may be a fresh struct or a
      # view over a `mut` cell's memory. The byte buffer is kept alive past the
      # call by `keepalive`.
      def fill_str(struct, value, keepalive, context)
        unless value.is_a?(String)
          raise MarshallError, "#{context}: Str expects a String, got #{value.class}"
        end

        pointer = keepalive.push(FFI::MemoryPointer.from_string(value.encode(Encoding::UTF_8))).last
        struct[:ptr] = pointer
        struct[:len] = pointer.size - 1
        struct
      end

      def fill_bytes(struct, value, keepalive, context)
        unless value.is_a?(String)
          raise MarshallError, "#{context}: Bytes expects a String, got #{value.class}"
        end

        pointer = keepalive.push(FFI::MemoryPointer.from_string(value.b)).last
        struct[:ptr] = pointer
        struct[:len] = pointer.size - 1
        struct
      end

      def encode_cstruct(name, value, keepalive, context)
        struct = cstruct_class(name).new
        fill(struct, @binding.declared_cstructs.fetch(name), value, keepalive, context)
        struct
      end

      def fill(struct, fields, value, keepalive, context)
        fields.each do |field, symbol|
          unless value.respond_to?(field)
            raise MarshallError, "#{context}: #{value.class} has no field '#{field}'"
          end

          field_context = "#{context}.#{field}"
          if cstruct?(symbol)
            fill(struct[field], @binding.declared_cstructs.fetch(symbol),
                 value.public_send(field), keepalive, field_context)
          else
            struct[field] = encode(symbol, value.public_send(field), keepalive,
                                   context: field_context)
          end
        end
      end

      # -- mut cells (in/out) --------------------------------------------------

      def build_cell(symbol, value, keepalive, context)
        base = base_symbol(symbol)
        pointer = allocate_cell(base, context)
        keepalive << pointer
        write_cell(base, pointer, value, keepalive, context)
        Cell.new(pointer, -> { read_cell(base, pointer, context) })
      end

      def allocate_cell(base, context)
        if cstruct?(base)
          FFI::MemoryPointer.new(cstruct_class(base))
        elsif base == :str
          FFI::MemoryPointer.new(XzStr)
        elsif base == :bytes
          FFI::MemoryPointer.new(XzBytes)
        else
          type = PRIMITIVE_TYPES[base]
          unless type && type != :void
            raise MarshallError, Values.unsupported(context, "mut_#{base}")
          end

          FFI::MemoryPointer.new(type)
        end
      end

      def write_cell(base, pointer, value, keepalive, context)
        case base
        when :bool then pointer.write_char(value ? 1 : 0)
        when :int then pointer.write_int64(Integer(value))
        when :usize then pointer.write_uint64(Integer(value))
        when :float then pointer.write_double(Float(value))
        when :char then pointer.write_char(Values.char_code(value, context))
        when :ptr then pointer.write_pointer(ffi_pointer(value, context) || FFI::Pointer::NULL)
        when :str then fill_str(XzStr.new(pointer), value, keepalive, context)
        when :bytes then fill_bytes(XzBytes.new(pointer), value, keepalive, context)
        else
          if cstruct?(base)
            fill(cstruct_class(base).new(pointer), @binding.declared_cstructs.fetch(base),
                 value, keepalive, context)
          else
            raise MarshallError, Values.unsupported(context, "mut_#{base}")
          end
        end
      end

      def read_cell(base, pointer, context)
        case base
        when :bool then pointer.read_char != 0
        when :int then pointer.read_int64
        when :usize then pointer.read_uint64
        when :float then pointer.read_double
        when :char then Values.char_string(pointer.read_char)
        when :ptr then Handle.new(pointer.read_pointer.to_i)
        when :str then decode_str(XzStr.new(pointer))
        when :bytes then decode_bytes(XzBytes.new(pointer))
        else
          if cstruct?(base)
            decode_cstruct(base, cstruct_class(base).new(pointer), context)
          else
            raise MarshallError, Values.unsupported(context, "mut_#{base}")
          end
        end
      end

      # -- decode (C -> Ruby) --------------------------------------------------

      def decode(symbol, raw, context:)
        case symbol
        when :unit then nil
        when :bool then raw ? true : false
        when :int, :usize then Integer(raw)
        when :float then Float(raw)
        when :char then Values.char_string(raw)
        when :ptr then Handle.new(raw.nil? ? 0 : raw.to_i)
        when :str then decode_str(raw)
        when :bytes then decode_bytes(raw)
        else
          if cstruct?(symbol)
            decode_cstruct(symbol, raw, context)
          else
            raise MarshallError, Values.unsupported(context, symbol)
          end
        end
      end

      def decode_str(struct)
        read_buffer(struct, Encoding::UTF_8)
      end

      def decode_bytes(struct)
        read_buffer(struct, Encoding::BINARY)
      end

      def read_buffer(struct, encoding)
        length = struct[:len].to_i
        pointer = struct[:ptr]
        return String.new(encoding: encoding) if length.zero? || pointer.nil? || pointer.null?

        pointer.read_bytes(length).force_encoding(encoding)
      end

      def decode_cstruct(name, struct, context)
        fields = @binding.declared_cstructs.fetch(name)
        values = fields.map do |field, symbol|
          raw = struct[field]
          value =
            if cstruct?(symbol)
              decode_cstruct(symbol, raw, "#{context}.#{field}")
            else
              decode(symbol, raw, context: "#{context}.#{field}")
            end
          [field, value]
        end.to_h
        @binding.const_get(name).new(**values)
      end
    end
  end
end
