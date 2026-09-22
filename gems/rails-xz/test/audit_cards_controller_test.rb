# frozen_string_literal: true

require "test_helper"

class AuditCardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @card = RailsXz::AuditCard.create!(
      module_name: "order",
      intent: "Computes the payable total.",
      declared_effects: ["none"],
      derived_effects: ["none"]
    )
  end

  test "the engine is mounted at /xz_audit" do
    assert_equal(
      { controller: "rails_xz/audit_cards", action: "index" },
      Rails.application.routes.recognize_path("/xz_audit/modules")
    )
  end

  test "index lists the cards" do
    get "/xz_audit/modules"

    assert_response :success
    assert_match "order", response.body
  end

  test "show renders one card" do
    get "/xz_audit/modules/#{@card.id}"

    assert_response :success
    assert_match "Computes the payable total.", response.body
  end

  test "approve records the decision and redirects" do
    post "/xz_audit/modules/#{@card.id}/approve"

    assert_response :redirect
    assert_equal "approved", @card.reload.status
    assert_equal "unknown", @card.decided_by
    refute_nil @card.decided_at
  end

  test "reject records the decision and redirects" do
    post "/xz_audit/modules/#{@card.id}/reject"

    assert_response :redirect
    assert_equal "rejected", @card.reload.status
    refute_nil @card.decided_at
  end
end
