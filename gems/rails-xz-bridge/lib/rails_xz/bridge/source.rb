# frozen_string_literal: true

module RailsXz
  module Bridge
    # Parser for the `@export` surface of an Xz module (a real `.xz` source,
    # with bodies). It extracts the `@export func` signatures and the `@cstruct
    # record` declarations and skips everything else — non-exported `func`,
    # `task`, `chan`, `extern`, `enum`, plain `record`, contracts, and bodies.
    # The output is the same `Interface::Parsed` the generator consumes, so the
    # `.xz`, `.h`, and `.xzint` inputs share one emission path
    # (docs/01-bridge.md section 2).
    #
    # This is a scanner, not a full parser. It tracks brace depth and skips
    # strings, characters, and comments, so a keyword inside a body is never
    # mistaken for a declaration; the front end of the Xz compiler remains
    # authoritative for the full grammar. Only `@export` functions cross the
    # boundary, so a non-exported declaration is skipped, not bound
    # (docs/01-bridge.md section 1).
    module Source
      module_function

      def parse(source, path: "module.xz")
        Parser.new(Tokenizer.new(source, path).tokens, path).parse
      end

      Token = Struct.new(:kind, :value, :line, :col, keyword_init: true)

      # Turns Xz source into tokens. Comments, strings, and characters are
      # skipped as opaque units so their contents (which may contain braces or
      # an `@export` substring) never reach the parser.
      class Tokenizer
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
                out << Token.new(kind: :punct, value: ch, line: line, col: col)
                i += 1
                col += 1
              end
            when '"', "'"
              out << Token.new(kind: :punct, value: ch, line: line, col: col)
              i, line, col = scan_quoted(i, line, col, len, ch)
            when "-"
              if @source[i + 1] == ">"
                out << Token.new(kind: :punct, value: "->", line: line, col: col)
                i += 2
                col += 2
              else
                out << Token.new(kind: :punct, value: ch, line: line, col: col)
                i += 1
                col += 1
              end
            else
              if ch.match?(/[A-Za-z_]/)
                j = i + 1
                j += 1 while j < len && @source[j].match?(/[A-Za-z0-9_]/)
                out << Token.new(kind: :ident, value: @source[i...j], line: line, col: col)
                col += j - i
                i = j
              else
                out << Token.new(kind: :punct, value: ch, line: line, col: col)
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
            raise SourceError, "#{loc(line, col)}unterminated block comment" if close.nil?

            advance_position(@source[i..close + 1], close + 2, line, col)
          end
        end

        # Consumes a quoted string or character literal, honoring backslash
        # escapes so an escaped delimiter does not end it early.
        def scan_quoted(i, line, col, len, delimiter)
          j = i + 1
          closed = false
          while j < len
            ch = @source[j]
            if ch == "\\"
              j += 2
            elsif ch == delimiter
              j += 1
              closed = true
              break
            else
              j += 1
            end
          end
          raise SourceError, "#{loc(line, col)}unterminated literal" unless closed

          advance_position(@source[i...j], j, line, col)
        end

        def advance_position(skipped, stop, line, col)
          newlines = skipped.count("\n")
          if newlines.zero?
            [stop, line, col + skipped.length]
          else
            [stop, line + newlines, skipped.length - skipped.rindex("\n")]
          end
        end

        def loc(line, col)
          "#{@path}:#{line}:#{col}: "
        end
      end

      # Scans top-level declarations. A declaration keyword inside a body is
      # unreachable because the body's braces raise the depth; the parser only
      # acts at depth zero.
      class Parser
        def initialize(tokens, path)
          @tokens = tokens
          @path = path
          @pos = 0
          @depth = 0
        end

        def parse
          cstructs = {}
          externs = []

          until eof?
            if at_punct?("{")
              @depth += 1
              advance
            elsif at_punct?("}")
              raise error("unbalanced '}'") if @depth.zero?

              @depth -= 1
              advance
            elsif @depth.zero? && at_punct?("@")
              handle_attribute(cstructs, externs)
            else
              advance
            end
          end

          raise error("unbalanced '{'") unless @depth.zero?

          Interface::Parsed.new(cstructs: cstructs, externs: externs)
        end

        private

        def handle_attribute(cstructs, externs)
          name = peek_ident
          case name
          when "export"
            externs << parse_export
          when "cstruct"
            record = parse_cstruct
            cstructs[record.name] = record
          else
            raise error("unsupported attribute '@#{name}'; expected '@export func' or '@cstruct record'")
          end
        end

        def parse_export
          consume_punct("@")
          expect_ident("export")
          if at_ident?("async")
            raise error("an '@export' function may not be async")
          end
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

          Interface::Extern.new(name: name, params: params, return_type: return_type,
                                type_params: type_params)
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

          Interface::Cstruct.new(name: name, fields: fields)
        end

        def parse_field
          name = expect_ident_value("field name")
          expect_punct(":")
          Interface::Field.new(name: name, type: parse_type)
        end

        def parse_params
          params = []
          return params if at_punct?(")")

          loop do
            mutable = false
            if at_ident?("mut")
              advance
              mutable = true
            elsif at_ident?("transfer")
              raise error("a 'transfer' parameter is legal only on an 'extern func'")
            end
            name = expect_ident_value("parameter name")
            expect_punct(":")
            params << Interface::Param.new(name: name, type: parse_type, mutable: mutable)
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

        # A union has no single C declaration, so it can never be an `@export`
        # signature; reject it here rather than emit a lossy binding.
        def parse_type
          nominal = parse_nominal
          if at_punct?("|")
            raise error("a union type is not C-representable in an '@export' signature")
          end

          nominal
        end

        def parse_nominal
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
          Interface::Type.new(name: name, args: args)
        end

        def peek_ident
          token = @tokens[@pos + 1]
          token && token.kind == :ident ? token.value : describe(token)
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

        def consume_punct(value)
          expect_punct(value)
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
          return "end of file" if token.nil? || token.kind == :eof

          token.kind == :ident ? "'#{token.value}'" : token.value.inspect
        end

        def error(message)
          SourceError.new("#{@path}:#{current.line}:#{current.col}: #{message}")
        end
      end
    end
  end
end
