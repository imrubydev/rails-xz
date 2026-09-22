# frozen_string_literal: true

module RailsXz
  module Bridge
    # Parser for the `.xzint` interface subset: a declaration-only Xz source
    # whose only top-level items are `extern func` signatures and `@cstruct
    # record` declarations (docs/10-ffi-interop.md; docs/01-bridge.md section 2).
    #
    # The front end of the Xz compiler is authoritative for the full grammar;
    # this parser covers exactly the subset an interface file may contain so the
    # Ruby generator can refuse anything else by name.
    module Interface
      Type = Struct.new(:name, :args, keyword_init: true) do
        def generic?
          !args.empty?
        end
      end

      Param = Struct.new(:name, :type, :mutable, keyword_init: true)
      Field = Struct.new(:name, :type, keyword_init: true)
      Cstruct = Struct.new(:name, :fields, keyword_init: true)
      Extern = Struct.new(:name, :params, :return_type, :type_params, keyword_init: true)
      Parsed = Struct.new(:cstructs, :externs, keyword_init: true)

      module_function

      def parse(source, path: "interface.xzint")
        Parser.new(Scanner.new(source, path).tokens, path).parse
      end

      Token = Struct.new(:kind, :value, :line, :col, keyword_init: true)

      # Turns `.xzint` text into tokens, skipping `//`, `///`, and `/* */`
      # comments. Only the punctuation the interface grammar uses is accepted,
      # so a stray character fails loudly instead of being misread.
      class Scanner
        PUNCTUATION = %w[( ) { } [ ] , : @].freeze

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
            when "/"
              scanned = scan_slash(i, line, col, len)
              if scanned
                i, line, col = scanned
              else
                out << Token.new(kind: :unknown, value: ch, line: line, col: col)
                i += 1
                col += 1
              end
            when "-"
              if @source[i + 1] == ">"
                out << Token.new(kind: :punct, value: "->", line: line, col: col)
                i += 2
                col += 2
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
            raise InterfaceError, "#{loc(line, col)}unterminated block comment" if close.nil?

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

      # Recursive-descent parser for the interface subset.
      class Parser
        # Top-level forms an interface file must not contain. They are rejected
        # by name, mirroring the compiler's `validate_interface`.
        REJECTED = %w[func task chan record enum].freeze

        def initialize(tokens, path)
          @tokens = tokens
          @path = path
          @pos = 0
        end

        def parse
          cstructs = {}
          externs = []

          until eof?
            if at_ident?("extern")
              extern = parse_extern
              externs << extern
            elsif at_punct?("@")
              cstruct = parse_cstruct
              cstructs[cstruct.name] = cstruct
            elsif REJECTED.include?(current.value)
              reject_declaration
            elsif current.kind == :unknown
              raise error("unexpected character #{current.value.inspect}")
            else
              raise error("expected 'extern func' or '@cstruct record', found #{describe(current)}")
            end
          end

          Parsed.new(cstructs: cstructs, externs: externs)
        end

        private

        def parse_extern
          consume_ident("extern")
          expect_ident("func")
          name = expect_ident_value("function name")
          type_params = parse_type_params
          expect_punct("(")
          params = parse_params
          expect_punct(")")
          return_type = nil
          if at_punct?("->")
            advance
            return_type = parse_type
          end

          Extern.new(name: name, params: params, return_type: return_type, type_params: type_params)
        end

        def parse_cstruct
          consume_punct("@")
          expect_ident("cstruct")
          expect_ident("record")
          name = expect_ident_value("record name")
          expect_punct("{")
          fields = []
          fields << parse_field until at_punct?("}")
          expect_punct("}")

          Cstruct.new(name: name, fields: fields)
        end

        def parse_field
          name = expect_ident_value("field name")
          expect_punct(":")
          Field.new(name: name, type: parse_type)
        end

        def parse_params
          params = []
          return params if at_punct?(")")

          loop do
            mutable = false
            if at_ident?("mut")
              advance
              mutable = true
            end
            name = expect_ident_value("parameter name")
            expect_punct(":")
            params << Param.new(name: name, type: parse_type, mutable: mutable)
            break unless at_punct?(",")

            advance
          end
          params
        end

        # `[T, U: Bound]` — parsed so a generic declaration is reported as a
        # generation error, not a syntax error.
        def parse_type_params
          return [] unless at_punct?("[")

          advance
          names = []
          loop do
            names << expect_ident_value("type parameter")
            if at_punct?(":")
              advance
              expect_ident_value("type parameter bound")
            end
            break unless at_punct?(",")

            advance
          end
          expect_punct("]")
          names
        end

        def parse_type
          name = expect_ident_value("type name")
          args = []
          if at_punct?("[")
            advance
            loop do
              args << parse_type
              break unless at_punct?(",")

              advance
            end
            expect_punct("]")
          end
          Type.new(name: name, args: args)
        end

        def reject_declaration
          kind = current.value
          advance
          name = current.kind == :ident ? advance.value : "<unknown>"
          raise error(
            "'.xzint' interface files may only declare 'extern func' and " \
            "'@cstruct record'; found #{kind} '#{name}'"
          )
        end

        def current
          @tokens[@pos]
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

        def expect_ident(value)
          raise error("expected '#{value}', found #{describe(current)}") unless at_ident?(value)

          advance
        end

        def consume_ident(value)
          expect_ident(value)
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

        def consume_punct(value)
          expect_punct(value)
        end

        def describe(token)
          token.kind == :eof ? "end of file" : token.value.inspect
        end

        def error(message)
          InterfaceError.new("#{@path}:#{current.line}:#{current.col}: #{message}")
        end
      end
    end
  end
end