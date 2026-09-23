# frozen_string_literal: true

require "strscan"

module RailsXz
  module Bridge
    module Interface
      # Reads the effect profile of an Xz module's `@export` functions from
      # their `@effects` intent comment. The compiler proves the declared
      # `@effects` equals the derived, transitive profile (error `I0020`), so the
      # declared label is the derived profile the bridge's GVL policy needs
      # (docs/01-bridge.md section 7).
      #
      # This is a focused reader, not a full parser: it scans top-level
      # declarations, skips function bodies, and returns a map from exported
      # function name to its labels. `none` is `[:none]`; a function with no
      # `@effects` line maps to `nil` (unknown).
      module ExportSource
        module_function

        def effects(source)
          Reader.new(source).effects
        end

        class Reader
          DOC = %r{///[^\n]*}
          LINE_COMMENT = %r{//[^\n]*}
          BLOCK_COMMENT = %r{/\*.*?\*/}m
          STRING = %r{"(?:\\.|[^"\\])*"}
          CHAR = %r{'(?:\\.|[^'\\])*'}
          EXPORT_FUNC = %r{@export\s+func\s+([A-Za-z_][A-Za-z0-9_]*)}
          EFFECTS = %r{\A\s*///\s*@effects\s*(.*)\z}
          WHITESPACE = /[ \t\r\n]+/

          def initialize(source)
            @scanner = StringScanner.new(source)
            @effects = {}
            @pending = nil
            @depth = 0
          end

          def effects
            until @scanner.eos?
              if @scanner.scan(DOC)
                @pending = merge_effects(@pending, @scanner.matched) if @depth.zero?
              elsif @scanner.scan(LINE_COMMENT) || @scanner.scan(BLOCK_COMMENT) ||
                    @scanner.scan(STRING) || @scanner.scan(CHAR) || @scanner.scan(WHITESPACE)
                next
              elsif @depth.zero? && @scanner.scan(EXPORT_FUNC)
                @effects[@scanner[1].to_sym] = @pending
                @pending = nil
              elsif @scanner.scan(/[{}]/)
                @depth += (@scanner.matched == "{" ? 1 : -1)
              else
                @pending = nil if @depth.zero?
                @scanner.getch
              end
            end
            @effects
          end

          private

          def merge_effects(pending, doc_line)
            match = EFFECTS.match(doc_line)
            return pending unless match

            parse_labels(match[1])
          end

          def parse_labels(text)
            labels = text.strip
            return [:none] if labels.empty? || labels == "none"

            labels.split(",").map { |label| label.strip.to_sym }
          end
        end
      end
    end
  end
end
