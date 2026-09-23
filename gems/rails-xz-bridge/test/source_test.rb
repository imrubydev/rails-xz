# frozen_string_literal: true

require "test_helper"

class SourceTest < Minitest::Test
  MODULE = <<~XZ
    /// Computes the payable total for an order.
    /// @intent  Sums line items and applies the tax rate.
    /// @effects none
    @export func payable_total(subtotal: Float, tax_rate: Float) -> Float
        post result >= 0.0
    {
        subtotal * (1.0 + tax_rate)
    }

    /// Parses an amount and writes it through an out-parameter.
    /// @intent  Returns 0 on success and writes the value to `out`.
    /// @effects mut
    @export func parse_amount(text: Str, mut out: Float) -> Int
    {
        0
    }

    @cstruct record Point {
        x: Int
        y: Int
    }
  XZ

  def parse(source)
    RailsXz::Bridge::Source.parse(source, path: "order.xz")
  end

  def test_parses_export_function_signatures
    parsed = parse(MODULE)

    assert_equal %w[payable_total parse_amount], parsed.externs.map(&:name)
    assert_equal %w[Float Float], parsed.externs[0].params.map { |p| p.type.name }
    assert_equal "Float", parsed.externs[0].return_type.name
  end

  def test_marks_mut_parameters
    amount = parse(MODULE).externs.last

    assert_equal "out", amount.params.last.name
    assert amount.params.last.mutable
    refute amount.params.first.mutable
  end

  def test_unit_return_has_no_return_type
    parsed = parse("@export func noop() { 0 }\n")

    assert_nil parsed.externs[0].return_type
  end

  def test_parses_cstruct_records
    point = parse(MODULE).cstructs.fetch("Point")

    assert_equal %w[x y], point.fields.map(&:name)
    assert_equal %w[Int Int], point.fields.map { |f| f.type.name }
  end

  def test_a_cstruct_may_follow_its_use
    parsed = parse(<<~XZ)
      @export func echo(p: Point) -> Point { p }
      @cstruct record Point { x: Int }
    XZ

    assert_equal "Point", parsed.externs[0].return_type.name
    assert parsed.cstructs.key?("Point")
  end

  def test_ignores_non_exported_declarations
    parsed = parse(<<~XZ)
      extern func free(p: Ptr) -> Unit
      task work { let x = 1 }
      enum Color { Red(Int), Blue }
      chan c: Chan[Int]
      func plain(a: Int) -> Int { a }
      record Plain { value: Int }
      @export func kept() -> Int { 0 }
    XZ

    assert_equal %w[kept], parsed.externs.map(&:name)
    assert_empty parsed.cstructs
  end

  def test_ignores_a_keyword_inside_a_string_literal
    parsed = parse(<<~XZ)
      @export func real() -> Int {
          let s = "not @export func evil(transfer x: Str) -> Int { }"
          0
      }
    XZ

    assert_equal %w[real], parsed.externs.map(&:name)
  end

  def test_ignores_braces_in_a_contract_expression
    parsed = parse(<<~XZ)
      /// @intent f
      /// @effects none
      @export func f(x: Int) -> Int
          post {1, 2} == {2, 1}
      {
          if x > 0 { x } else { 0 }
      }
    XZ

    assert_equal %w[f], parsed.externs.map(&:name)
  end

  def test_parses_generic_types_for_the_generator_to_reject
    parsed = parse("@export func first(values: List[Int]) -> Int { 0 }\n")
    type = parsed.externs[0].params[0].type

    assert_equal "List", type.name
    assert_equal "Int", type.args[0].name
  end

  def test_rejects_a_union_type
    error = assert_raises(RailsXz::Bridge::SourceError) do
      parse("@export func f(x: Int) -> Int | Float { x }\n")
    end

    assert_match(/union type is not C-representable/, error.message)
  end

  def test_rejects_a_transfer_parameter
    error = assert_raises(RailsXz::Bridge::SourceError) do
      parse("@export func f(transfer x: Str) -> Int { 0 }\n")
    end

    assert_match(/transfer' parameter is legal only on an 'extern func'/, error.message)
  end

  def test_rejects_an_unknown_attribute
    error = assert_raises(RailsXz::Bridge::SourceError) do
      parse("@weird func f() -> Int { 0 }\n")
    end

    assert_match(/unsupported attribute '@weird'/, error.message)
  end

  def test_rejects_an_async_export
    error = assert_raises(RailsXz::Bridge::SourceError) do
      parse("@export async func f() -> Int { 0 }\n")
    end

    assert_match(/may not be async/, error.message)
  end

  def test_rejects_an_unbalanced_body
    error = assert_raises(RailsXz::Bridge::SourceError) do
      parse("@export func f() -> Int { 0\n")
    end

    assert_match(/unbalanced '\{'/, error.message)
  end

  def test_rejects_a_stray_closing_brace
    error = assert_raises(RailsXz::Bridge::SourceError) do
      parse("@export func f() -> Int { 0 }\n}\n")
    end

    assert_match(/unbalanced '\}'/, error.message)
  end
end
