# frozen_string_literal: true

module RailsXz
  module Bridge
    # Parser for the C header `xz build --shared` writes beside a shared
    # library. The header is an honest, complete description of the ABI, so the
    # generator can bind a library from it without hand-written signatures
    # (docs/01-bridge.md sections 1, 2, and 6).
    #
    # The compiler has already rejected anything that is not C-representable, so
    # this parser maps the emitted C types back to the `.xzint` subset
    # (`Interface::Parsed`) and refuses anything it does not recognize rather
    # than guessing a layout.
    module Header
      # The two by-value carrier structs the compiler always emits. Their field
      # types (`const char*`, `size_t`) are not part of the Xz type surface, so
      # they are skipped rather than mapped.
      CARRIERS = %w[XzStr XzBytes].freeze

      # C base type => Xz type name. `void` is handled separately because its
      # meaning depends on pointer depth.
      PRIMITIVES = {
        "bool" => "Bool",
        "int64_t" => "Int",
        "uint64_t" => "usize",
        "double" => "Float",
        "char" => "Char",
        "XzStr" => "Str",
        "XzBytes" => "Bytes"
      }.freeze

      module_function

      def parse(source, path: "library.h")
        Parser.new(Tokenizer.new(source, path).tokens, path).parse
      end

      Token = Struct.new(:kind, :value, :line, :col, keyword_init: true)
      CType = Struct.new(:base, :pointers, :const, keyword_init: true)

      # Turns C header text into tokens, skipping `//`, `///`, `/* */`
      # comments and whole preprocessor lines (`#ifndef`, `#include`, ...).
      # Only the punctuation the emitted header uses is accepted, so a stray
      # character fails loudly.
      class Tokenizer
        PUNCTUATION = %w[{ } ( ) ; , *].freeze

        def initialize(source, path)
          @source = source
          @path = path
        end

        def tokens
          out = []
          i = 0
          line = 1
          col = 1
          len = @source.length

          while i < len
            ch = @source[i]
            case ch
            when "\n"
              line += 1
              col = 1
              i += 1
            when " ", "\t", "\r"
              i += 1
              col += 1
            when "#"
              i = @source.index("\n", i) || len
            when "/"
              scanned = scan_slash(i, line, col, len)
              if scanned
                i, line, col = scanned
              else
                out << Token.new(kind: :unknown, value: ch, line: line, col: col)
                i += 1
                col += 1
              end
            when *PUNCTUATION
              out << Token.new(kind: :punct, value: ch, line: line, col: col)
              i += 1
              col += 1
            else
              if ch.match?(/[A-Za-z_]/)
                j = i + 1
                j += 1 while j < len && @source[j].match?(/[A-Za-z0-9_]/)
                out << Token.new(kind: :ident, value: @source[i...j], line: line, col: col)
                col += j - i
                i = j
              else
                out << Token.new(kind: :unknown, value: ch, line: line, col: col)
                i += 1
                col += 1
              end
            end
          end

          out << Token.new(kind: :eof, value: nil, line: line, col: col)
          out
        end

        private

        def scan_slash(i, line, col, len)
          case @source[i + 1]
          when "/"
            newline = @source.index("\n", i) || len
            [newline, line, col]
          when "*"
            close = @source.index("*/", i + 2)
            raise HeaderError, "#{loc(line, col)}unterminated block comment" if close.nil?

            skipped = @source[i..close + 1]
            newlines = skipped.count("\n")
            if newlines.zero?
              [close + 2, line, col + skipped.length]
            else
              [close + 2, line + newlines, skipped.length - skipped.rindex("\n")]
            end
          end
        end

        def loc(line, col)
          "#{@path}:#{line}:#{col}: "
        end
      end

      # Recursive-descent parser for the emitted header. `typedef struct` forms
      # become `@cstruct` records; a prototype becomes an `extern` declaration.
      class Parser
        def initialize(tokens, path)
          @tokens = tokens
          @path = path
          @pos = 0
          @cstructs = {}
        end

        def parse
          externs = []

          until eof?
            if at_ident?("typedef")
              record = parse_typedef
              @cstructs[record.name] = record if record
            elsif current.kind == :unknown
              raise error("unexpected character #{current.value.inspect}")
            else
              externs << parse_prototype
            end
          end

          Interface::Parsed.new(cstructs: @cstructs, externs: externs)
        end

        private

        def parse_typedef
          consume_ident("typedef")
          expect_ident("struct")
          name = expect_ident_value("struct name")
          expect_punct("{")

          if CARRIERS.include?(name)
            skip_struct_body
            expect_punct("}")
            expect_ident_value("typedef name")
            expect_punct(";")
            return nil
          end

          fields = []
          fields << parse_field until at_punct?("}")
          expect_punct("}")
          alias_name = expect_ident_value("typedef name")
          raise error("typedef '#{alias_name}' does not name struct '#{name}'") unless alias_name == name

          expect_punct(";")
          Interface::Cstruct.new(name: name, fields: fields)
        end

        def skip_struct_body
          depth = 0
          loop do
            raise error("unterminated struct body") if eof?

            if at_punct?("{")
              depth += 1
            elsif at_punct?("}")
              return if depth.zero?

              depth -= 1
            end
            advance
          end
        end

        def parse_field
          ctype = parse_c_type
          name = expect_ident_value("field name")
          expect_punct(";")
          mapped = to_xz(ctype, context: "field '#{name}'")
          if mapped[:mutable]
            raise error("field '#{name}' is a pointer to a value; a C struct cannot carry one")
          end

          Interface::Field.new(name: name, type: mapped[:type])
        end

        def parse_prototype
          ret = parse_c_type
          name = expect_ident_value("function name")
          expect_punct("(")
          params = parse_params
          expect_punct(")")
          expect_punct(";")

          Interface::Extern.new(
            name: name,
            params: params,
            return_type: to_xz_return(ret, context: "return of '#{name}'"),
            type_params: []
          )
        end

        def parse_params
          if at_ident?("void") && peek_punct?(1, ")")
            advance
            return []
          end

          params = []
          return params if at_punct?(")")

          loop do
            ctype = parse_c_type
            name = expect_ident_value("parameter name")
            mapped = to_xz(ctype, context: "parameter '#{name}'")
            params << Interface::Param.new(name: name, type: mapped[:type], mutable: mapped[:mutable])
            break unless at_punct?(",")

            advance
          end
          params
        end

        def parse_c_type
          const = false
          if at_ident?("const")
            advance
            const = true
          end
          base = expect_ident_value("type name")
          pointers = 0
          while at_punct?("*")
            advance
            pointers += 1
          end
          CType.new(base: base, pointers: pointers, const: const)
        end

        # Maps a C type to an Xz type plus its mutability. A pointer to a value
        # type is the C in/out convention (`mut`); `void*` is a `Ptr` and
        # `void**` is a `mut Ptr`.
        def to_xz(ctype, context:)
          if ctype.base == "void"
            case ctype.pointers
            when 1 then return { type: type("Ptr"), mutable: false }
            when 2 then return { type: type("Ptr"), mutable: true }
            else
              raise error("#{context}: cannot represent #{'void' + ('*' * ctype.pointers)}")
            end
          end

          name = PRIMITIVES[ctype.base]
          name = ctype.base if name.nil? && @cstructs.key?(ctype.base)
          raise error("#{context}: unknown C type '#{ctype.base}'") if name.nil?

          case ctype.pointers
          when 0 then { type: type(name), mutable: false }
          when 1 then { type: type(name), mutable: true }
          else
            raise error("#{context}: pointer depth #{ctype.pointers} is not C-representable")
          end
        end

        def to_xz_return(ctype, context:)
          return nil if ctype.base == "void" && ctype.pointers.zero?

          mapped = to_xz(ctype, context: context)
          raise error("#{context}: a returned pointer to a value is not C-representable") if mapped[:mutable]

          mapped[:type]
        end

        def type(name)
          Interface::Type.new(name: name, args: [])
        end

        def current
          @tokens[@pos]
        end

        def peek_punct?(offset, value)
          token = @tokens[@pos + offset]
          token && token.kind == :punct && token.value == value
        end

        def advance
          token = @tokens[@pos]
          @pos += 1
          token
        end

        def eof?
          current.kind == :eof
        end

        def at_ident?(value)
          current.kind == :ident && current.value == value
        end

        def at_punct?(value)
          current.kind == :punct && current.value == value
        end

        def consume_ident(value)
          expect_ident(value)
        end

        def expect_ident(value)
          raise error("expected '#{value}', found #{describe(current)}") unless at_ident?(value)

          advance
        end

        def expect_ident_value(what)
          raise error("expected #{what}, found #{describe(current)}") unless current.kind == :ident

          advance.value
        end

        def expect_punct(value)
          unless at_punct?(value)
            raise error("expected '#{value}', found #{describe(current)}")
          end

          advance
        end

        def describe(token)
          token.kind == :eof ? "end of file" : token.value.inspect
        end

        def error(message)
          HeaderError.new("#{@path}:#{current.line}:#{current.col}: #{message}")
        end
      end
    end
  end
end
