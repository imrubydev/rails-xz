# frozen_string_literal: true

require "test_helper"

class DiffComponentTest < ActiveSupport::TestCase
  DIFF = <<~DIFF
    @@ -1,2 +1,2 @@
    -/// @effects none
    +/// @effects io
     fn total() -> Float { 1.0 }
  DIFF

  def component(diff: DIFF, diagnostics: nil)
    RailsXz::DiffComponent.new(diff: diff, diagnostics: diagnostics)
  end

  test "is blank without a diff" do
    refute component(diff: nil).present?
    refute component(diff: "").present?
  end

  test "parses the stored diff into lines" do
    assert component.present?
    assert_equal 4, component.lines.size
  end

  test "line_class marks each diff kind" do
    classes = component.lines.map { |line| component.line_class(line) }

    assert_includes classes, "xz-diff__line xz-diff__line--removed xz-diff__line--contract"
    assert_includes classes, "xz-diff__line xz-diff__line--added xz-diff__line--contract"
    assert_includes classes, "xz-diff__line xz-diff__line--context"
  end

  test "exposes the clearing run attempts and codes" do
    card = component(diagnostics: { "attempts" => 2, "codes" => %w[I0020] })

    assert_equal 2, card.attempts
    assert_equal %w[I0020], card.codes
    assert card.run_present?
  end

  test "a run is absent when diagnostics carry nothing" do
    refute component.run_present?
  end

  test "tolerates the database default for diagnostics" do
    assert_equal [], component(diagnostics: []).codes
    refute component(diagnostics: []).run_present?
  end
end