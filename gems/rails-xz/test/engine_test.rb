# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def test_version_is_pinned
    assert_match(/\A\d+\.\d+\.\d+\z/, RailsXz::VERSION)
  end
end