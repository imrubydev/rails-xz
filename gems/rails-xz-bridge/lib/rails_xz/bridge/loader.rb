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

      def initialize(path, expected_xz_version: nil)
        @path = path
        @handle = nil
        @ffi_library = nil
        @expected_xz_version = expected_xz_version
      end

      def load!
        unless File.exist?(@path)
          raise VersionError, "cannot load #{@path}: file does not exist"
        end

        verify_version!
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

      # Reads the companion metadata written next to the library by the build
      # step. Phase 1 replaces this stub with the real metadata read.
      def verify_version!
        return if @expected_xz_version.nil?

        actual = read_compiler_version
        return if actual == @expected_xz_version

        raise VersionError,
              "#{@path} was built by xz #{actual}, expected #{@expected_xz_version}"
      end

      def read_compiler_version
        nil
      end
    end
  end
end