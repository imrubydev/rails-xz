# frozen_string_literal: true

module RailsXz
  module Agent
    # One structured diagnostic from `xz check-json`.
    #
    # Schema: version, severity, code, message, category, span, suggestion.
    Diagnostic = Struct.new(
      :severity, :code, :message, :category, :span, :suggestion,
      keyword_init: true
    ) do
      def self.from_json(hash)
        new(
          severity: hash["severity"],
          code: hash["code"],
          message: hash["message"],
          category: hash["category"],
          span: hash["span"],
          suggestion: hash["suggestion"]
        )
      end

      def error?
        severity == "error"
      end

      def line
        span && span.dig("start", 0)
      end

      def confidence
        suggestion && suggestion["confidence"] || 0.0
      end

      # Ranking used by the repair prompt (see docs/02-agent-loop.md §4).
      CATEGORY_ORDER = %w[lex parse resolve type intent].freeze

      def rank
        [error? ? 0 : 1, CATEGORY_ORDER.index(category) || CATEGORY_ORDER.size, -confidence]
      end
    end
  end
end