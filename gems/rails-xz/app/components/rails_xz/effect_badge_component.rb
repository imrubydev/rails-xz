# frozen_string_literal: true

module RailsXz
  # Renders one compiler-derived effect label as a colored badge.
  #
  # The mapping is the contract from docs/03-audit-engine.md section 3. The
  # compiler only ever emits the five known labels (an unknown one is I0024), so
  # an unknown label here is a data bug and raises rather than rendering an
  # uncolored badge.
  class EffectBadgeComponent < ViewComponent::Base
    UnknownEffect = Class.new(StandardError)

    BADGES = {
      "none"   => { label: "PURE",          color: "green" },
      "mut"    => { label: "MUTATES_STATE", color: "amber" },
      "io"     => { label: "IO",            color: "blue" },
      "chan"   => { label: "CONCURRENCY",   color: "purple" },
      "extern" => { label: "EXTERNAL_FFI",  color: "red" }
    }.freeze

    attr_reader :effect, :label, :color

    def self.badge_for(effect)
      BADGES[effect.to_s]
    end

    def initialize(effect)
      @effect = effect.to_s
      badge = self.class.badge_for(@effect)
      raise UnknownEffect, "unknown effect #{effect.inspect}" unless badge

      @label = badge[:label]
      @color = badge[:color]
    end
  end
end