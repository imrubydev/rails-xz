# frozen_string_literal: true

require "fiddle"

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
    # Only `@export` symbols are expected to resolve; the loader raises
    # SymbolError rather than returning nil for an unknown name.
    class Loader
      EXTENSIONS = %w[.so .dylib .dll].freeze

      attr_reader :path

      def initialize(path, expected_xz_version: nil)
        @path = path
        @handle = nil
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

      def function(name, args, ret)
        raise SymbolError, "library not loaded; call #load!" unless @handle

        Fiddle::Function.new(@handle[name.to_s], args, ret)
      rescue Fiddle::DLError => e
        raise SymbolError, "missing symbol #{name.inspect}: #{e.message}"
      end

      # Development-only hot reload. Never call while a call is in flight.
      def reload!
        @handle = nil
        load!
      end

      def close
        @handle = nil
      end

      private

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