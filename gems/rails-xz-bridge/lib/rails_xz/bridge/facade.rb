# frozen_string_literal: true

require "fiddle"

module RailsXz
  module Bridge
    # Runtime for a generated binding module. A generated module `extend`s this
    # module and declares its shared object, `@cstruct`s, and functions; the
    # declarations become singleton methods that marshal Ruby values across the
    # C ABI through the Loader. See docs/01-bridge.md section 6.2.
    #
    # This slice marshals scalars (`Bool`, `Int`, `usize`, `Float`, `Char`).
    # `Str`, `Bytes`, `Ptr` handles, `@cstruct` by value, and `mut` cells fail
    # with MarshallError rather than degrading silently; their slices follow.
    module Facade
      FIDDLE_TYPES = {
        bool: Fiddle::TYPE_CHAR,
        int: Fiddle::TYPE_LONG_LONG,
        usize: Fiddle::TYPE_ULONG_LONG,
        float: Fiddle::TYPE_DOUBLE,
        char: Fiddle::TYPE_CHAR
      }.freeze

      def self.extended(base)
        base.instance_variable_set(:@xz_library, nil)
        base.instance_variable_set(:@xz_cstructs, {})
        base.instance_variable_set(:@xz_functions, {})
        base.instance_variable_set(:@xz_loader, nil)
      end

      # Records the shared object the binding loads. Resolution is lazy.
      def xz_library(path)
        @xz_library = path
      end

      # Defines a Ruby `Data` constant with the record's field order. The C
      # layout stays authoritative; the Ruby class never reorders fields.
      def xz_cstruct(name, fields)
        const_set(name, Data.define(*fields.keys))
        @xz_cstructs[name] = fields.freeze
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
      # restores lazy loading.
      attr_writer :xz_loader

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

        raise MarshallError, _unsupported(context, symbol)
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
        when :char then _char_code(value, context)
        else raise MarshallError, _unsupported(context, symbol)
        end
      end

      def _xz_decode(symbol, raw, context:)
        case symbol
        when :unit then nil
        when :bool then raw != 0
        when :int, :usize then Integer(raw)
        when :float then Float(raw)
        when :char then _char_string(raw)
        else raise MarshallError, _unsupported(context, symbol)
        end
      end

      def _char_code(value, context)
        value = value.to_s
        unless value.length == 1
          raise MarshallError, "#{context}: Char expects a one-character String, got #{value.inspect}"
        end

        value.ord
      end

      def _char_string(raw)
        raw.is_a?(Integer) ? raw.chr : raw.to_s
      end

      def _unsupported(context, symbol)
        "#{context}: marshalling '#{symbol}' is not implemented yet " \
          "(docs/01-bridge.md section 6.2)"
      end
    end
  end
end