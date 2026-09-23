# frozen_string_literal: true

module RailsXz
  module Bridge
    # Build-time generator: emits a Ruby binding module from an `.xzint`
    # interface file, the C header `xz build --shared` writes, or an `.xz`
    # module's `@export` surface. The output mirrors `xz pkg gen --lang python`:
    # a module named after the source stem, a `Data` class per `@cstruct`, and a
    # typed declaration per function, all through RailsXz::Bridge::Facade
    # (docs/01-bridge.md sections 2 and 6).
    #
    #   Generator.new("libcurl.xzint", lib: "libcurl.so").generate
    #   Generator.new("libcurl.h", lib: "libcurl.so").generate
    #   Generator.new("order.xz", lib: "liborder.so").generate
    #   # => String of Ruby source for Xz::Bindings::Libcurl
    #
    # A `.h` path is read as a generated C header, an `.xz` path as an Xz module,
    # and anything else as an `.xzint` interface. A signature that is not
    # C-representable is a hard error, never a lossy cast (ARCHITECTURE.md
    # section 3.1).
    class Generator
      PLATFORM_SUFFIX =
        case RUBY_PLATFORM
        when /darwin/ then ".dylib"
        when /mswin|mingw/ then ".dll"
        else ".so"
        end

      # The effect labels the Xz compiler accepts (docs/01-bridge.md section 7).
      EFFECT_LABELS = %i[none mut io chan extern].freeze

      def initialize(interface_path, lib: nil, module_name: nil, source: nil, effects: nil)
        @interface_path = interface_path
        @lib = lib
        @module_name = module_name
        @source = source
        @effects = effects || {}
      end

      def generate
        parsed = parse
        read_source_effects if xz_source?
        validate!(parsed)
        emit(parsed)
      end

      private

      def parse
        return Header.parse(source, path: display_path) if header_source?
        return Source.parse(source, path: display_path) if xz_source?

        Interface.parse(source, path: display_path)
      end

      def header_source?
        File.extname(display_path.to_s) == ".h"
      end

      def xz_source?
        File.extname(display_path.to_s) == ".xz"
      end

      # An `.xz` module carries the compiler-verified `@effects` of each
      # `@export` function in its intent comment, so the binding reads the GVL
      # profile from the same source that supplies the signatures
      # (docs/01-bridge.md section 7). A profile passed to `new` still wins.
      def read_source_effects
        @effects = Interface::ExportSource.effects(source).merge(@effects)
      end

      # The ABI digest is only defined for a compiler header: an `.xzint`
      # interface is a hand-written boundary, not the compiler's own ABI
      # description, so the binding it produces is not pinned
      # (docs/01-bridge.md section 3).
      def abi_digest
        return @abi_digest if defined?(@abi_digest)

        @abi_digest = header_source? ? Header.digest(source) : nil
      end

      def source
        @source ||= File.read(@interface_path)
      end

      def display_path
        @interface_path || "interface.xzint"
      end

      def stem
        @stem ||= File.basename(display_path.to_s, ".*")
      end

      def module_name
        @module_name || "Xz::Bindings::#{camelize(stem)}"
      end

      def lib_name
        @lib || "#{stem}#{PLATFORM_SUFFIX}"
      end

      def camelize(value)
        value.split(/[^A-Za-z0-9]+/).reject(&:empty?).map(&:capitalize).join
      end

      # -- validation ----------------------------------------------------------

      def validate!(parsed)
        names = parsed.cstructs.keys

        parsed.cstructs.each_value do |record|
          record.fields.each do |field|
            check_type!(field.type, names, as_return: false,
                        context: "@cstruct #{record.name} field '#{field.name}'")
          end
        end
        reject_cycles!(parsed.cstructs)

        parsed.externs.each do |extern|
          check_not_generic!(extern)
          extern.params.each do |param|
            check_type!(param.type, names, as_return: false,
                        context: "extern '#{extern.name}' parameter '#{param.name}'")
          end
          next if extern.return_type.nil?

          check_type!(extern.return_type, names, as_return: true,
                      context: "extern '#{extern.name}' return")
        end
        validate_effects!
      end

      def validate_effects!
        @effects.each do |name, labels|
          next if labels.nil?

          unless labels.is_a?(Array)
            raise GenerationError,
                  "effects for '#{name}' must be an array of labels, got #{labels.class}"
          end
          if labels.include?(:none) && labels.length > 1
            raise GenerationError,
                  "effects for '#{name}': 'none' cannot be combined with other effects"
          end
          unknown = labels - EFFECT_LABELS
          unless unknown.empty?
            raise GenerationError,
                  "effects for '#{name}': unknown effect(s) #{unknown.inspect} " \
                  "(allowed: #{EFFECT_LABELS.join(', ')})"
          end
        end
      end

      def check_not_generic!(extern)
        return if extern.type_params.empty?

        raise GenerationError,
              "extern '#{extern.name}' is generic; a C ABI export cannot carry a " \
              "type parameter (docs/01-bridge.md section 1)"
      end

      def check_type!(type, names, as_return:, context:)
        if type.generic?
          raise GenerationError,
                "#{context}: '#{render_type(type)}' is not C-representable"
        end

        name = type.name
        if Types.primitive?(name)
          if Types.return_only?(name) && !as_return
            raise GenerationError,
                  "#{context}: Unit is allowed only as a return"
          end
          return
        end

        return if names.include?(name)

        raise GenerationError, "#{context}: unknown type '#{name}'"
      end

      def reject_cycles!(cstructs)
        state = {}
        cstructs.each_key do |name|
          walk = lambda do |current|
            case state[current]
            when :done then return
            when :open
              raise GenerationError,
                    "@cstruct '#{current}' nests itself; a C struct cannot be cyclic"
            end
            state[current] = :open
            cstructs.fetch(current).fields.each do |field|
              ref = record_reference(field.type, cstructs)
              walk.call(ref) if ref
            end
            state[current] = :done
          end
          walk.call(name)
        end
      end

      def record_reference(type, cstructs)
        return nil if type.generic?

        type.name if cstructs.key?(type.name)
      end

      # -- emission ------------------------------------------------------------

      def emit(parsed)
        lines = []
        lines << "# Generated by rails-xz-bridge from #{display_path}. Do not edit."
        lines << 'require "rails-xz-bridge"'
        lines << ""
        lines << "module #{module_name}"
        lines << "  extend RailsXz::Bridge::Facade"
        lines << ""
        lines << "  xz_library #{double_quoted(lib_name)}"
        lines << "  xz_abi_digest #{double_quoted(abi_digest)}" if abi_digest

        ordered_cstructs(parsed).each do |record|
          lines << ""
          lines << "  # @cstruct #{record.name} { #{field_doc(record)} }"
          lines << "  xz_cstruct :#{record.name}, #{brace_list(field_symbols(record))}"
        end

        parsed.externs.each do |extern|
          lines << ""
          lines << "  # #{signature_doc(extern)}"
          lines << "  xz_func :#{extern.name}, #{brace_list(param_symbols(extern))}, " \
                   "#{type_symbol(extern.return_type).inspect}#{effects_option(extern)}"
        end

        lines << "end"
        "#{lines.join("\n")}\n"
      end

      def ordered_cstructs(parsed)
        emitted = []
        visiting = {}
        visit = lambda do |record|
          return if emitted.include?(record.name) || visiting[record.name]

          visiting[record.name] = true
          record.fields.each do |field|
            ref = record_reference(field.type, parsed.cstructs)
            visit.call(parsed.cstructs.fetch(ref)) if ref
          end
          visiting.delete(record.name)
          emitted << record
        end
        parsed.cstructs.each_value { |record| visit.call(record) }
        emitted
      end

      def field_doc(record)
        record.fields.map { |field| "#{field.name}: #{render_type(field.type)}" }.join(", ")
      end

      def field_symbols(record)
        record.fields.map { |field| "#{field.name}: #{type_symbol(field.type).inspect}" }.join(", ")
      end

      def param_symbols(extern)
        extern.params.map do |param|
          "#{param.name}: #{type_symbol(param.type, mutable: param.mutable).inspect}"
        end.join(", ")
      end

      def brace_list(body)
        body.empty? ? "{}" : "{ #{body} }"
      end

      def signature_doc(extern)
        params = extern.params.map do |param|
          "#{param.mutable ? 'mut ' : ''}#{param.name}: #{render_type(param.type)}"
        end.join(", ")
        returns = extern.return_type ? " -> #{render_type(extern.return_type)}" : ""
        "extern func #{extern.name}(#{params})#{returns}"
      end

      def type_symbol(type, mutable: false)
        return :unit if type.nil?

        base = Types.primitive_symbol(type.name) || :"#{type.name}"
        mutable ? :"mut_#{base}" : base
      end

      # The GVL policy reads the compiler-verified effect profile from the
      # declaration. A function with no profile emits nothing, so the loader
      # treats it as unknown and releases the GVL (docs/01-bridge.md section 7).
      def effects_option(extern)
        labels = @effects[extern.name.to_sym]
        return "" if labels.nil?

        ", effects: #{labels.inspect}"
      end

      def render_type(type)
        return type.name if type.args.empty?

        "#{type.name}[#{type.args.map { |arg| render_type(arg) }.join(', ')}]"
      end

      # The library name is user-supplied and lands in generated source, so it
      # is escaped rather than interpolated raw.
      def double_quoted(value)
        escaped = value.to_s.gsub("\\", "\\\\").gsub('"', '\\"')
        "\"#{escaped}\""
      end
    end
  end
end