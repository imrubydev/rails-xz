# frozen_string_literal: true

module RailsXz
  # One reviewable module card: intent, effect badges, diff, and the decision.
  # See docs/03-audit-engine.md sections 2 and 3.
  #
  # The derived effects are the authoritative risk surface, so they render as
  # colored badges; the declared list is shown as text until the side-by-side
  # comparison and @trusted marker land.
  class AuditCardComponent < ViewComponent::Base
    attr_reader :card

    def initialize(card:)
      @card = card
    end
  end
end