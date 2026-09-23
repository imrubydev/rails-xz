# frozen_string_literal: true

require "fiddle"
require "ffi"

module RailsXz
  module Bridge
    # Loads a compiled Xz shared library and exposes its @export symbols.
    #
    #   loader = Loader.new("vendor/xz/liborder.so")
    #   loader.load!
    #   fn = loader.function("payable_total",
    #                        [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE],
    #                        Fiddle::TYPE_DOUBLE)
    #
    # `function` binds a Fiddle signature; `ffi_function` binds an ffi signature
    # for calls that cross a by-value struct (docs/01-bridge.md section 3). Only
    # `@export` symbols are expected to resolve; the loader raises SymbolError
    # rather than returning nil for an unknown name.
    class Loader
      EXTENSIONS = %w[.so .dylib .dll].freeze

      attr_reader :path

      def initialize(path, expected_abi_digest: nil)
        @path = path
        @handle = nil
        @ffi_library = nil
        @expected_abi_digest = expected_abi_digest
      end

      def load!
        unless File.exist?(@path)
          raise VersionError, "cannot load #{@path}: file does not exist"
        end

        verify_abi_digest!
        @handle = Fiddle.dlopen(@path)
        self
      end

      def loaded?
        !@handle.nil?
      end

      # `need_gvl` mirrors Fiddle: true holds the GVL across the call, false
      # (the default) releases it. The Facade decides from the function's
      # effect profile (docs/01-bridge.md section 7).
      def function(name, args, ret, need_gvl: false)
        raise SymbolError, "library not loaded; call #load!" unless @handle

        Fiddle::Function.new(@handle[name.to_s], args, ret, need_gvl: need_gvl)
      rescue Fiddle::DLError => e
        raise SymbolError, "missing symbol #{name.inspect}: #{e.message}"
      end

      # Binds a symbol through the ffi gem. Used for signatures Fiddle cannot
      # express, namely a C struct passed or returned by value. `blocking`
      # mirrors ffi: true releases the GVL across the call, false (the default)
      # holds it.
      def ffi_function(name, ret, args, blocking: false)
        raise SymbolError, "library not loaded; call #load!" unless @handle

        FFI::Function.new(ret, args, ffi_library.find_function(name.to_s), blocking: blocking)
      rescue FFI::NotFoundError => e
        raise SymbolError, "missing symbol #{name.inspect}: #{e.message}"
      end

      # Development-only hot reload. Never call while a call is in flight.
      def reload!
        @handle = nil
        @ffi_library = nil
        load!
      end

      def close
        @handle = nil
        @ffi_library = nil
      end

      private

      def ffi_library
        @ffi_library ||= FFI::DynamicLibrary.open(
          @path,
          FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_LOCAL
        )
      end

      # The compiler exposes no version string, so the binding pins the digest of
      # the header `xz build --shared` wrote beside the library — the compiler's
      # own description of the ABI (docs/01-bridge.md section 3). A different or
      # missing header means the library no longer matches the binding, so the
      # loader refuses to bind it rather than call a mismatched ABI.
      def verify_abi_digest!
        return if @expected_abi_digest.nil?

        actual = abi_digest
        if actual.nil?
          raise VersionError,
                "#{@path}: companion header #{header_path} not found; " \
                "cannot verify the pinned ABI digest #{@expected_abi_digest}"
        end
        return if actual == @expected_abi_digest

        raise VersionError,
              "#{@path} does not match the pinned ABI digest " \
              "(binding #{@expected_abi_digest}, header #{actual})"
      end

      # The digest of the header beside the library, or nil when there is none.
      def abi_digest
        return nil unless File.exist?(header_path)

        Header.digest(File.read(header_path))
      end

      def header_path
        "#{@path.sub(/\.[^.\/]+\z/, '')}.h"
      end
    end
  end
end