# frozen_string_literal: true

require "test_helper"

class LoaderTest < Minitest::Test
  def test_missing_file_raises_version_error
    loader = RailsXz::Bridge::Loader.new("does/not/exist.so")

    assert_raises(RailsXz::Bridge::VersionError) { loader.load! }
  end

  def test_function_before_load_raises_symbol_error
    loader = RailsXz::Bridge::Loader.new("does/not/exist.so")

    assert_raises(RailsXz::Bridge::SymbolError) do
      loader.function("nope", [], Fiddle::TYPE_VOID)
    end
  end
end