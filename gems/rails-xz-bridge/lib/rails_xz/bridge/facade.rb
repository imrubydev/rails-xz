# frozen_string_literal: true

require "fiddle"

module RailsXz
  module Bridge
    # Runtime for a generated binding module. A generated module `extend`s this
    # module and declares its shared object, `@cstruct`s, and functions; the
    # declarations become singleton methods that marshal Ruby values across the
    # C ABI. See docs/01-bridge.md section 6.2.
    #
    # A signature that crosses a by-value aggregate (`Str`, `Bytes`, or a
    # `@cstruct`) is bound through FfiMarshaller, because Fiddle cannot pass or
    # return a C struct by value. Scalar- and pointer-only signatures use
    # Fiddle, so the common path keeps no native dependency beyond the gem
    # itself. `mut` cells still fail with MarshallError until their slice lands.
    module Facade
      FIDDLE_TYPES = {
        bool: Fiddle::TYPE_CHAR,
        int: Fiddle::TYPE_LONG_LONG,
        usize: Fiddle::TYPE_ULONG_LONG,
        float: Fiddle::TYPE_DOUBLE,
        char: Fiddle::TYPE_CHAR,
        ptr: Fiddle::TYPE_VOIDP
      }.freeze

      def self.extended(base)
        base.instance_variable_set(:@xz_library, nil)
        base.instance_variable_set(:@xz_cstructs, {})
        base.instance_variable_set(:@xz_functions, {})
        base.instance_variable_set(:@xz_loader, nil)
        base.instance_variable_set(:@xz_ffi_marshaller, nil)
      end

      # Records the shared object the binding loads. Resolution is lazy.
      def xz_library(path)
        @xz_library = path
        @xz_ffi_marshaller = nil
      end

      # Defines a Ruby `Data` constant with the record's field order. The C
      # layout stays authoritative; the Ruby class never reorders fields.
      def xz_cstruct(name, fields)
        const_set(name, Data.define(*fields.keys))
        @xz_cstructs[name] = fields.freeze
        @xz_ffi_marshaller = nil
        const_get(name)
      end

      # Declares one C function. The generated method takes positional Ruby
      # arguments and returns the Xz value.
      def xz_func(name, params, returns)
        @xz_functions[name] = { params: params.freeze, returns: returns }.freeze
        define_singleton_method(name) do |*args|
          _xz_call(name, params, returns, args)
        end
      end

      # Injects a loader (a test double, or a preloaded Loader). Passing nil
      # restores lazy loading. Resets the ffi marshaller so it rebinds.
      def xz_loader=(loader)
        @xz_ffi_marshaller = nil
        @xz_loader = loader
      end

      def declared_functions
        @xz_functions.dup
      end

      def declared_cstructs
        @xz_cstructs.dup
      end

      def xz_loaded?
        !@xz_loader.nil?
      end

      def xz_load!
        xz_loader
        self
      end

      private

      def xz_loader
        @xz_loader ||= begin
          if @xz_library.nil?
            raise MarshallError, "no xz_library declared for #{self}"
          end

          Loader.new(@xz_library).tap(&:load!)
        end
      end

      def _xz_call(name, params, returns, args)
        unless args.length == params.length
          raise ArgumentError,
                "#{name} expects #{params.length} argument(s), got #{args.length}"
        end

        if _xz_ffi?(params, returns)
          _xz_ffi_marshaller.call(name, params, returns, args)
        else
          _xz_call_fiddle(name, params, returns, args)
        end
      end

      # A by-value aggregate has no Fiddle representation, so its signature
      # takes the ffi path (docs/01-bridge.md section 3).
      def _xz_ffi?(params, returns)
        params.any? { |_param, symbol| _xz_aggregate?(symbol) } || _xz_aggregate?(returns)
      end

      def _xz_aggregate?(symbol)
        symbol == :str || symbol == :bytes || @xz_cstructs.key?(symbol)
      end

      def _xz_ffi_marshaller
        @xz_ffi_marshaller ||= FfiMarshaller.new(self, xz_loader)
      end

      def _xz_call_fiddle(name, params, returns, args)
        fiddle_args = params.map do |param_name, symbol|
          _xz_fiddle_type(symbol, context: "#{name} parameter '#{param_name}'")
        end
        fiddle_return = _xz_fiddle_return_type(returns, name)

        encoded = params.each_with_index.map do |(param_name, symbol), index|
          _xz_encode(symbol, args[index], context: "#{name} parameter '#{param_name}'")
        end

        function = xz_loader.function(name.to_s, fiddle_args, fiddle_return)
        _xz_decode(returns, function.call(*encoded), context: "#{name} return")
      end

      def _xz_fiddle_type(symbol, context:)
        type = FIDDLE_TYPES[symbol]
        return type if type

        raise MarshallError, Values.unsupported(context, symbol)
      end

      def _xz_fiddle_return_type(returns, name)
        return Fiddle::TYPE_VOID if returns == :unit

        _xz_fiddle_type(returns, context: "#{name} return")
      end

      def _xz_encode(symbol, value, context:)
        case symbol
        when :bool then value ? 1 : 0
        when :int, :usize then Integer(value)
        when :float then Float(value)
        when :char then Values.char_code(value, context)
        when :ptr then Values.handle_address(value, context)
        else raise MarshallError, Values.unsupported(context, symbol)
        end
      end

      def _xz_decode(symbol, raw, context:)
        case symbol
        when :unit then nil
        when :bool then raw != 0
        when :int, :usize then Integer(raw)
        when :float then Float(raw)
        when :char then Values.char_string(raw)
        when :ptr then Handle.new(raw.nil? ? 0 : raw)
        else raise MarshallError, Values.unsupported(context, symbol)
        end
      end
    end
  end
end
