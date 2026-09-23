# frozen_string_literal: true

require "test_helper"

class UnifiedDiffTest < Minitest::Test
  DIFF = <<~DIFF
    --- a/app/xz/order.xz
    +++ b/app/xz/order.xz
    @@ -1,4 +1,5 @@
     /// @intent  Computes the payable total.
    -/// @effects none
    +/// @effects io
     fn payable_total(subtotal: Float, tax_rate: Float) -> Float {
    -  return subtotal
    +  return subtotal * (1.0 + tax_rate)
     }
  DIFF

  def diff
    RailsXz::UnifiedDiff.new(DIFF)
  end

  def test_classifies_file_hunk_context_added_and_removed_lines
    assert_equal(
      %i[file file hunk context removed added context removed added context],
      diff.lines.map(&:kind)
    )
  end

  def test_line_predicates_match_the_kind
    added = diff.lines.find(&:added?)
    removed = diff.lines.find(&:removed?)

    assert_equal "+", added.marker
    assert_equal "-", removed.marker
    refute added.removed?
    assert removed.removed?
    assert diff.lines.find(&:context?).context?
  end

  def test_keeps_the_text_without_the_diff_marker
    added = diff.lines.find { |line| line.text.include?("@effects io") }

    assert_equal "/// @effects io", added.text
  end

  def test_contract_changes_returns_only_changed_lines_carrying_a_directive
    changes = diff.contract_changes.map(&:text)

    assert_equal ["/// @effects none", "/// @effects io"], changes
  end

  def test_a_body_change_is_not_a_contract_change
    refute diff.lines.find { |line| line.text.include?("1.0 + tax_rate") }.contract?
  end

  def test_an_empty_diff_has_no_lines
    assert_empty RailsXz::UnifiedDiff.new(nil).lines
    assert_empty RailsXz::UnifiedDiff.new("").lines
  end
end