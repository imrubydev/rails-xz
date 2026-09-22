# frozen_string_literal: true

require "test_helper"

class AuditCardComponentTest < ActiveSupport::TestCase
  def component(declared:, derived:)
    card = RailsXz::AuditCard.new(declared_effects: declared, derived_effects: derived)
    RailsXz::AuditCardComponent.new(card: card)
  end

  test "effects_match? ignores order" do
    assert component(declared: %w[io none], derived: %w[none io]).effects_match?
  end

  test "effects_match? is true when both are empty" do
    assert component(declared: [], derived: []).effects_match?
  end

  test "effects_match? detects a divergence" do
    refute component(declared: %w[none], derived: %w[io]).effects_match?
  end
end