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

  test "show renders the audit card with effect badges" do
    get "/xz_audit/modules/#{@card.id}"

    assert_response :success
    assert_match "xz-audit-card", response.body
    assert_match "Computes the payable total.", response.body
    assert_match "xz-effect-badge--green", response.body
    assert_match "PURE", response.body
    assert_match "Approve", response.body
    assert_match "Reject", response.body
  end

  test "show colors each derived effect" do
    card = RailsXz::AuditCard.create!(
      module_name: "io_module",
      declared_effects: %w[io extern],
      derived_effects: %w[io extern]
    )

    get "/xz_audit/modules/#{card.id}"

    assert_response :success
    assert_match "xz-effect-badge--blue", response.body
    assert_match "xz-effect-badge--red", response.body
    assert_match "EXTERNAL_FFI", response.body
  end

  test "show renders declared and derived effects side by side" do
    get "/xz_audit/modules/#{@card.id}"

    assert_response :success
    assert_match "Declared effects", response.body
    assert_match "Derived effects", response.body
    assert_match 'data-effects-match="true"', response.body
  end

  test "show warns when declared and derived effects diverge" do
    card = RailsXz::AuditCard.create!(
      module_name: "diverged",
      declared_effects: %w[none],
      derived_effects: %w[io]
    )

    get "/xz_audit/modules/#{card.id}"

    assert_response :success
    assert_match 'data-effects-match="false"', response.body
    assert_match "I0020", response.body
  end

  test "show marks trusted claims with their note" do
    card = RailsXz::AuditCard.create!(
      module_name: "trusted_module",
      declared_effects: %w[none],
      derived_effects: %w[none],
      trusted_claims: [{ "claim" => "no overflow", "note" => "reviewed by alice" }]
    )

    get "/xz_audit/modules/#{card.id}"

    assert_response :success
    assert_match "xz-trusted-marker", response.body
    assert_match "no overflow", response.body
    assert_match "reviewed by alice", response.body
  end

  test "show omits the trusted marker when there are no claims" do
    get "/xz_audit/modules/#{@card.id}"

    assert_response :success
    refute_match "xz-trusted-marker", response.body
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

  test "approve over Turbo Streams replaces the card in place" do
    post "/xz_audit/modules/#{@card.id}/approve", as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(
      %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(@card)}"),
      response.body
    )
    assert_match 'data-status="approved"', response.body
    assert_equal "approved", @card.reload.status
  end

  test "reject over Turbo Streams replaces the card in place" do
    post "/xz_audit/modules/#{@card.id}/reject", as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(
      %(action="replace" target="#{ActionView::RecordIdentifier.dom_id(@card)}"),
      response.body
    )
    assert_match 'data-status="rejected"', response.body
    assert_equal "rejected", @card.reload.status
  end
end
