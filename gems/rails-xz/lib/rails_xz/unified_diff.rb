# frozen_string_literal: true

module RailsXz
  # Parses the unified diff the Engine stores against the last approved revision
  # (docs/03-audit-engine.md section 4). Pure text, no Rails dependency, so the
  # classification a reviewer relies on is testable on its own.
  class UnifiedDiff
    # The contract directives Xz recognizes (docs/02-syntax.md). A changed line
    # that carries one is a claim change, which the card must surface as loudly
    # as a body change.
    CONTRACT_PATTERN = /@(?:intent|requires|ensures|effects|trusted)\b/

    Line = Struct.new(:kind, :marker, :text) do
      def added? = kind == :added

      def removed? = kind == :removed

      def context? = kind == :context

      def changed? = added? || removed?

      def contract?
        text.to_s.match?(RailsXz::UnifiedDiff::CONTRACT_PATTERN)
      end
    end

    attr_reader :lines

    def initialize(text)
      @lines = parse(text.to_s)
    end

    # Added/removed lines that carry a contract directive, in diff order. The
    # diff view highlights these so a silent `@effects`/`@trusted` change cannot
    # ride along with a body edit.
    def contract_changes
      lines.select { |line| line.changed? && line.contract? }
    end

    private

    def parse(text)
      text.each_line.map { |raw| build_line(raw.chomp) }
    end

    def build_line(line)
      case line
      when /\A\+\+\+/ then Line.new(:file, "+", line[4..])
      when /\A---/ then Line.new(:file, "-", line[4..])
      when /\A@@/ then Line.new(:hunk, "", line)
      when /\A\+/ then Line.new(:added, "+", line[1..])
      when /\A-/ then Line.new(:removed, "-", line[1..])
      when /\A\\/ then Line.new(:meta, "", line)
      when /\A / then Line.new(:context, " ", line[1..])
      else Line.new(:context, "", line)
      end
    end
  end
end