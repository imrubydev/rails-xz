# frozen_string_literal: true

require "test_helper"

class HandleTest < Minitest::Test
  def test_exposes_the_address_and_nullness
    handle = RailsXz::Bridge::Handle.new(0x10)

    assert_equal 0x10, handle.to_i
    refute handle.null?
    assert RailsXz::Bridge::Handle.new(0).null?
  end

  def test_equality_is_by_address
    assert_equal RailsXz::Bridge::Handle.new(7), RailsXz::Bridge::Handle.new(7)
    refute_equal RailsXz::Bridge::Handle.new(7), RailsXz::Bridge::Handle.new(8)
  end

  def test_is_frozen
    assert RailsXz::Bridge::Handle.new(1).frozen?
  end
end
