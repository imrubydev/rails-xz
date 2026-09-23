# frozen_string_literal: true

class AddApprovalFieldsToRailsXzAuditCards < ActiveRecord::Migration[7.1]
  def change
    add_column :rails_xz_audit_cards, :source_path, :string
    add_column :rails_xz_audit_cards, :commit_sha, :string
  end
end
