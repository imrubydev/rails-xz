# frozen_string_literal: true

class CreateRailsXzAuditCards < ActiveRecord::Migration[7.1]
  def change
    create_table :rails_xz_audit_cards do |t|
      t.string :module_name, null: false
      t.text :signature
      t.text :intent
      t.jsonb :declared_effects, default: []
      t.jsonb :derived_effects, default: []
      t.jsonb :trusted_claims, default: []
      t.jsonb :diagnostics, default: []
      t.text :diff
      t.string :status, null: false, default: "pending"
      t.string :decided_by
      t.datetime :decided_at

      t.timestamps
    end

    add_index :rails_xz_audit_cards, :status
  end
end