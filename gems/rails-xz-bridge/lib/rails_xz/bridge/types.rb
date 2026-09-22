# frozen_string_literal: true

module RailsXz
  module Bridge
    # The C-representable Xz type surface and its Ruby binding symbols. This is
    # the single source of truth shared by the generator (which validates and
    # emits symbols) and the Facade runtime (which resolves them to Fiddle
    # types). See docs/01-bridge.md sections 4 and 6.1.
    module Types
      # Xz primitive name => generated Ruby type symbol.
      PRIMITIVE_SYMBOLS = {
        "Bool" => :bool,
        "Int" => :int,
        "usize" => :usize,
        "Float" => :float,
        "Char" => :char,
        "Str" => :str,
        "Bytes" => :bytes,
        "Ptr" => :ptr,
        "Unit" => :unit
      }.freeze

      # `Unit` has no C declaration as an argument; it is valid as a return only.
      RETURN_ONLY = %w[Unit].freeze

      module_function

      def primitive?(name)
        PRIMITIVE_SYMBOLS.key?(name)
      end

      def primitive_symbol(name)
        PRIMITIVE_SYMBOLS[name]
      end

      def return_only?(name)
        RETURN_ONLY.include?(name)
      end
    end
  end
end