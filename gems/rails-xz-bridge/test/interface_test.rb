# frozen_string_literal: true

require "test_helper"

class InterfaceTest < Minitest::Test
  def parse(source)
    source = "@interface foreign\n#{source}" unless source.start_with?("@interface")
    RailsXz::Bridge::Interface.parse(source, path: "lib.xzint")
  end

  def test_requires_the_interface_marker
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      RailsXz::Bridge::Interface.parse("extern func noop()\n", path: "lib.xzint")
    end

    assert_match(/exactly one '@interface/, error.message)
  end

  def test_reads_the_interface_kind
    assert_equal :foreign, parse("extern func noop()\n").kind
    assert_equal :export, parse("@interface export\nextern func noop()\n").kind
  end

  def test_rejects_a_marker_that_is_not_first
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("extern func noop()\n@interface foreign\n")
    end

    assert_match(/must be the first construct/, error.message)
  end

  def test_rejects_an_unknown_interface_kind
    error = assert_raises(RailsXz::Bridge::InterfaceError) do
      parse("@interface mixed\nextern func noop()\n")
    end

    assert_match(/expected 'export' or 'foreign'/, error.message)
  end

  def test_parses_a_transfer_parameter
    parsed = parse("extern func write(transfer data: Bytes) -> Int\n")
    param = parsed.externs[0].params[0]

    assert param.transfer
    refute param.mutable
  end

  def test_parses_a_transfer_return_and_release_symbol
    parsed = parse(<<~XZINT)
      extern func free(ptr: Ptr) -> Unit
      extern func strdup(s: Str) -> transfer Str release free
    XZINT
    extern = parsed.externs[1]

    assert extern.transfer_return
    assert_equal "free", extern.release
    assert_equal "Str", extern.return_type.name
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