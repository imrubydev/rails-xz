# frozen_string_literal: true

require "test_helper"

class EffectBadgeComponentTest < ActiveSupport::TestCase
  MAPPING = {
    "none"   => ["PURE", "green"],
    "mut"    => ["MUTATES_STATE", "amber"],
    "io"     => ["IO", "blue"],
    "chan"   => ["CONCURRENCY", "purple"],
    "extern" => ["EXTERNAL_FFI", "red"]
  }.freeze

  test "every effect maps to its badge name and color" do
    MAPPING.each do |effect, (label, color)|
      badge = RailsXz::EffectBadgeComponent.new(effect)

      assert_equal effect, badge.effect
      assert_equal label, badge.label
      assert_equal color, badge.color
    end
  end

  test "symbol labels are accepted" do
    badge = RailsXz::EffectBadgeComponent.new(:io)

    assert_equal "io", badge.effect
    assert_equal "IO", badge.label
  end

  test "badge_for exposes the mapping without rendering" do
    assert_equal({ label: "PURE", color: "green" }, RailsXz::EffectBadgeComponent.badge_for("none"))
    assert_nil RailsXz::EffectBadgeComponent.badge_for("teleport")
  end

  test "an unknown effect raises" do
    assert_raises(RailsXz::EffectBadgeComponent::UnknownEffect) do
      RailsXz::EffectBadgeComponent.new("teleport")
    end
  end
end