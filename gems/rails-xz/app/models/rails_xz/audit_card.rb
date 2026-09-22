# frozen_string_literal: true

module RailsXz
  # One AI-generated Xz module awaiting or carrying a human decision.
  # See docs/03-audit-engine.md §7.
  class AuditCard < ApplicationRecord
    self.table_name = "rails_xz_audit_cards"

    STATUSES = %w[pending approved rejected blocked].freeze

    validates :module_name, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :awaiting, -> { where(status: "pending") }

    def approve!(by:)
      update!(status: "approved", decided_by: by, decided_at: Time.current)
    end

    def reject!(by:)
      update!(status: "rejected", decided_by: by, decided_at: Time.current)
    end
  end
end