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
    # `@cstruct`) or carries a `mut` cell is bound through FfiMarshaller, because
    # Fiddle cannot pass or return a C struct by value and ffi allocates a typed
    # in/out cell. Scalar- and pointer-only signatures use Fiddle, so the common
    # path keeps no native dependency beyond the gem itself.
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
        base.instance_variable_set(:@xz_abi_digest, nil)
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

      # Records the ABI digest the binding was generated from. When present, the
      # loader refuses to bind a library whose companion header no longer matches
      # (docs/01-bridge.md section 3).
      def xz_abi_digest(digest)
        @xz_abi_digest = digest
        @xz_loader = nil
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
      #
      # `effects` is the compiler-verified effect profile of an Xz `@export`
      # function (for example `[:none]`, `[:io]`); `release_gvl` forces the GVL
      # to be released for this call. See docs/01-bridge.md section 7.
      def xz_func(name, params, returns, effects: nil, release_gvl: false)
        @xz_functions[name] = {
          params: params.freeze,
          returns: returns,
          effects: effects,
          release_gvl: release_gvl
        }.freeze
        define_singleton_method(name) do |*args|
          _xz_call(name, params, returns, args, effects: effects, release_gvl: release_gvl)
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

      def xz_pinned_abi_digest
        @xz_abi_digest
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

          Loader.new(@xz_library, expected_abi_digest: @xz_abi_digest).tap(&:load!)
        end
      end

      def _xz_call(name, params, returns, args, effects:, release_gvl:)
        unless args.length == params.length
          raise ArgumentError,
                "#{name} expects #{params.length} argument(s), got #{args.length}"
        end

        release = _xz_release_gvl?(effects, release_gvl)
        if _xz_ffi?(params, returns)
          _xz_ffi_marshaller.call(name, params, returns, args, release_gvl: release)
        else
          _xz_call_fiddle(name, params, returns, args, release)
        end
      end

      # The GVL is released unless the compiler proved the function pure
      # (`@effects none`), because an unknown or non-`none` profile may block and
      # must not stall the whole process. `release_gvl: true` forces release even
      # for a pure function. See docs/01-bridge.md section 7.
      def _xz_release_gvl?(effects, explicit)
        return true if explicit
        return false if effects == [:none]

        true
      end

      # A by-value aggregate or a `mut` cell has no Fiddle representation, so its
      # signature takes the ffi path (docs/01-bridge.md section 3).
      def _xz_ffi?(params, returns)
        params.any? { |_param, symbol| _xz_aggregate?(symbol) || _xz_mut?(symbol) } ||
          _xz_aggregate?(returns)
      end

      def _xz_aggregate?(symbol)
        symbol == :str || symbol == :bytes || @xz_cstructs.key?(symbol)
      end

      def _xz_mut?(symbol)
        symbol.to_s.start_with?("mut_")
      end

      def _xz_ffi_marshaller
        @xz_ffi_marshaller ||= FfiMarshaller.new(self, xz_loader)
      end

      def _xz_call_fiddle(name, params, returns, args, release_gvl)
        fiddle_args = params.map do |param_name, symbol|
          _xz_fiddle_type(symbol, context: "#{name} parameter '#{param_name}'")
        end
        fiddle_return = _xz_fiddle_return_type(returns, name)

        encoded = params.each_with_index.map do |(param_name, symbol), index|
          _xz_encode(symbol, args[index], context: "#{name} parameter '#{param_name}'")
        end

        function = xz_loader.function(name.to_s, fiddle_args, fiddle_return,
                                      need_gvl: !release_gvl)
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
