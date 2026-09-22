# frozen_string_literal: true

module RailsXz
  # One reviewable module card: intent, declared vs derived effects, trusted
  # markers, diff, and the decision. See docs/03-audit-engine.md sections 2 and 3.
  class AuditCardComponent < ViewComponent::Base
    attr_reader :card

    def initialize(card:)
      @card = card
    end

    # The declared claim and the derived profile must agree (I0020). The card
    # renders them side by side and calls out a divergence.
    def effects_match?
      card.declared_effects.sort == card.derived_effects.sort
    end
  end
end