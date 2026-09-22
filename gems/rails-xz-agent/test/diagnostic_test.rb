# frozen_string_literal: true

require "test_helper"

class DiagnosticTest < Minitest::Test
  def diagnostic(category:, confidence:, severity: "error")
    RailsXz::Agent::Diagnostic.from_json(
      "severity" => severity,
      "category" => category,
      "suggestion" => { "confidence" => confidence }
    )
  end

  def test_rank_orders_earlier_phases_first
    parse = diagnostic(category: "parse", confidence: 0.5)
    intent = diagnostic(category: "intent", confidence: 0.9)

    assert_operator parse.rank, :<, intent.rank
  end

  def test_rank_breaks_ties_by_confidence
    low = diagnostic(category: "type", confidence: 0.1)
    high = diagnostic(category: "type", confidence: 0.8)

    assert_operator high.rank, :<, low.rank
  end
end