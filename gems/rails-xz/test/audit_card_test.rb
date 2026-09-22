# frozen_string_literal: true

require "test_helper"

class AuditCardTest < ActiveSupport::TestCase
  setup do
    RailsXz::AuditCard.delete_all
  end

  def build_card(**attrs)
    RailsXz::AuditCard.new({ module_name: "order" }.merge(attrs))
  end

  def create_card(**attrs)
    build_card(**attrs).tap(&:save!)
  end

  test "module_name is required" do
    card = build_card(module_name: nil)

    refute card.valid?
    assert card.errors.of_kind?(:module_name, :blank)
  end

  test "status defaults to pending" do
    assert_equal "pending", create_card.status
  end

  test "status must be one of the declared statuses" do
    card = build_card(status: "shipped")

    refute card.valid?
    assert card.errors.of_kind?(:status, :inclusion)
  end

  test "every declared status is accepted" do
    RailsXz::AuditCard::STATUSES.each do |status|
      assert build_card(status: status).valid?, "#{status} should be valid"
    end
  end

  test "approve! records the decision" do
    card = create_card
    before = Time.current

    card.approve!(by: "alice")

    assert_equal "approved", card.status
    assert_equal "alice", card.decided_by
    refute_nil card.decided_at
    assert_operator card.decided_at, :>=, before
  end

  test "approve! persists the decision" do
    id = create_card.id

    RailsXz::AuditCard.find(id).approve!(by: "alice")

    assert_equal "approved", RailsXz::AuditCard.find(id).status
  end

  test "reject! records the decision" do
    card = create_card

    card.reject!(by: "bob")

    assert_equal "rejected", card.status
    assert_equal "bob", card.decided_by
    refute_nil card.decided_at
  end

  test "awaiting scope returns only pending cards" do
    pending = create_card(module_name: "pending_one")
    approved = create_card(module_name: "approved_one")
    approved.approve!(by: "alice")
    rejected = create_card(module_name: "rejected_one")
    rejected.reject!(by: "bob")

    assert_equal [pending.id], RailsXz::AuditCard.awaiting.pluck(:id)
  end

  test "json columns default to empty arrays" do
    card = create_card

    assert_equal [], card.declared_effects
    assert_equal [], card.derived_effects
    assert_equal [], card.trusted_claims
    assert_equal [], card.diagnostics
  end
end