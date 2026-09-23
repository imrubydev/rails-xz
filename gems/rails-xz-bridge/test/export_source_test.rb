# frozen_string_literal: true

require "test_helper"

class ExportSourceTest < Minitest::Test
  def effects(source)
    RailsXz::Bridge::Interface::ExportSource.effects(source)
  end

  def test_reads_none_from_an_exported_function
    source = <<~XZ
      /// Adds two integers.
      /// @intent  Returns a + b.
      /// @effects none
      @export func add(a: Int, b: Int) -> Int {
          a + b
      }
    XZ

    assert_equal({ add: [:none] }, effects(source))
  end

  def test_reads_a_comma_separated_profile
    source = <<~XZ
      /// @effects io, chan
      @export func stream(x: Int) -> Int {
          x
      }
    XZ

    assert_equal({ stream: %i[io chan] }, effects(source))
  end

  def test_ignores_a_non_exported_function
    source = <<~XZ
      /// @effects io
      func helper(x: Int) -> Int {
          x
      }
    XZ

    assert_empty effects(source)
  end

  def test_ignores_effects_lines_inside_a_body
    source = <<~XZ
      /// @effects none
      @export func first(x: Int) -> Int {
          let s = "/// @effects io"
          x
      }

      /// @effects io
      @export func second(x: Int) -> Int {
          x
      }
    XZ

    assert_equal({ first: [:none], second: [:io] }, effects(source))
  end

  def test_a_function_without_an_effects_line_is_unknown
    source = <<~XZ
      /// @intent  No profile declared.
      @export func bare(x: Int) -> Int {
          x
      }
    XZ

    assert_equal({ bare: nil }, effects(source))
  end

  def test_handles_cstructs_and_comments_between_functions
    source = <<~XZ
      // a leading line comment
      @cstruct record Vec2 {
          x: Int
          y: Int
      }

      /* a block comment with @export func fake(x: Int) */
      /// @effects none
      @export func sum(v: Vec2) -> Int {
          v.x + v.y
      }
    XZ

    assert_equal({ sum: [:none] }, effects(source))
  end

  def test_reads_the_repository_examples
    order = File.expand_path("../../../examples/order.xz", __dir__)
    parse_amount = File.expand_path("../../../examples/parse_amount.xz", __dir__)

    assert_equal({ payable_total: [:none] }, effects(File.read(order)))
    assert_equal({ parse_amount: [:mut] }, effects(File.read(parse_amount)))
  end
end
