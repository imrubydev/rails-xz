# frozen_string_literal: true

module RailsXz
  # A distinct marker for one unproven `@trusted` claim, so the reviewer sees the
  # proof gap next to the effect badge it affects. See
  # docs/03-audit-engine.md section 3.
  class TrustedMarkerComponent < ViewComponent::Base
    attr_reader :claim, :note

    def initialize(claim:, note: nil)
      @claim = claim.to_s
      @note = note.to_s.presence
    end
  end
end