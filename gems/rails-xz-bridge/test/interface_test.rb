# frozen_string_literal: true

require "test_helper"

class InterfaceTest < Minitest::Test
  def parse(source)
    RailsXz::Bridge::Interface.parse(source, path: "lib.xzint")
  end

  def test_parses_extern_signatures
    parsed = parse(<<~XZINT)
      extern func curl_easy_init() -> Ptr
      extern func curl_easy_setopt(handle: Ptr, option: Int, param: Ptr) -> Int
      extern func curl_easy_cleanup(handle: Ptr)
    XZINT

    assert_equal %w[curl_easy_init curl_easy_setopt curl_easy_cleanup],
                 parsed.externs.map(&:name)

    setopt = parsed.externs[1]
    assert_equal %w[handle option param], setopt.params.map(&:name)
    assert_equal %w[Ptr Int Ptr], setopt.params.map { |p| p.type.name }
    assert_equal "Int", setopt.return_type.name

    assert_nil parsed.externs[2].return_type
  end

  def test_parses_mut_parameters
    parsed = parse("extern func parse_amount(text: Str, mut out: Float) -> Int\n")
    out = parsed.externs[0].params[1]

    assert out.mutable
    assert_equal "Float", out.type.name
    refute parsed.externs[0].params[0].mutable
  end

  def test_parses_cstruct_records
    parsed = parse(<<~XZINT)
      @cstruct record Color {
          r: usize
          g: usize
          b: usize
          a: usize
      }
    XZINT

    color = parsed.cstructs.fetch("Color")
    assert_equal %w[r g b a], color.fields.map(&:name)
    assert_equal %w[usize usize usize usize], color.fields.map { |f| f.type.name }
  end

  def test_skips_line_doc_and_block_comments
    parsed = parse(<<~XZINT)
      // line comment
      /// doc comment with extern func ignored
      extern func noop()
      /* block
         comment */
      @cstruct record Empty {
      }
    XZINT

    assert_equal ["noop"], parsed.externs.map(&:name)
    assert parsed.cstructs.key?("Empty")
  end

  def test_rejects_a_function_with_a_body
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("extern func puts(s: Str) -> Int\nfunc helper() -> Int {\n    1\n}\n")
    end

    assert_match(/func 'helper'/, error.message)
  end

  def test_rejects_a_plain_record
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("record Buffer {\n    ptr: Ptr\n}\n")
    end

    assert_match(/record 'Buffer'/, error.message)
  end

  def test_rejects_unexpected_characters
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("extern func noop() -> Int = 1\n")
    end

    assert_match(/unexpected character/, error.message)
  end

  def test_rejects_an_unterminated_block_comment
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("/* never closed\nextern func noop()\n")
    end

    assert_match(/unterminated block comment/, error.message)
  end

  def test_rejects_a_plain_record_annotation
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("@export func ping()\n")
    end

    assert_match(/expected 'cstruct'/, error.message)
  end
end