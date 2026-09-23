# frozen_string_literal: true

module RailsXz
  # Renders a candidate's unified diff against the last approved revision plus
  # the diagnostic run that cleared it. See docs/03-audit-engine.md section 4.
  #
  # `diff` is the stored unified diff; `diagnostics` is the clearing run
  # (`{ "attempts" => Integer, "codes" => [String] }`). A blank diff or a run
  # that carries neither field renders nothing rather than an empty frame.
  class DiffComponent < ViewComponent::Base
    attr_reader :diff, :diagnostics

    def initialize(diff:, diagnostics: nil)
      @diff = diff.to_s
      @diagnostics = diagnostics.is_a?(Hash) ? diagnostics : {}
    end

    def present?
      diff.present?
    end

    def lines
      @lines ||= UnifiedDiff.new(diff).lines
    end

    def attempts
      diagnostics["attempts"]
    end

    def codes
      Array(diagnostics["codes"]).map(&:to_s)
    end

    def run_present?
      attempts.present? || codes.any?
    end

    def line_class(line)
      classes = ["xz-diff__line", "xz-diff__line--#{line.kind}"]
      classes << "xz-diff__line--contract" if line.changed? && line.contract?
      classes.join(" ")
    end
  end
end