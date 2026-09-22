# frozen_string_literal: true

require "test_helper"

class TrustedMarkerComponentTest < ActiveSupport::TestCase
  test "exposes the claim and its review note" do
    marker = RailsXz::TrustedMarkerComponent.new(
      claim: "no overflow",
      note: "reviewed by alice"
    )

    assert_equal "no overflow", marker.claim
    assert_equal "reviewed by alice", marker.note
  end

  test "the note is optional" do
    marker = RailsXz::TrustedMarkerComponent.new(claim: "no overflow")

    assert_equal "no overflow", marker.claim
    assert_nil marker.note
  end
end