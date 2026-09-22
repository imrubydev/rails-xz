# frozen_string_literal: true

require "test_helper"

class GeneratorTest < Minitest::Test
  LIBRARY = <<~XZINT
    extern func curl_easy_init() -> Ptr
    extern func curl_easy_setopt(handle: Ptr, option: Int, param: Ptr) -> Int
    extern func curl_easy_cleanup(handle: Ptr)

    @cstruct record curl_slist {
        data: Str
        next: Ptr
    }
  XZINT

  def generate(source, **options)
    RailsXz::Bridge::Generator
      .new("libcurl.xzint", source: source, **options)
      .generate
  end

  def test_emits_a_facade_module_named_after_the_stem
    output = generate("extern func noop()\n")

    assert_includes output, "module Xz::Bindings::Libcurl"
    assert_includes output, "extend RailsXz::Bridge::Facade"
    assert_includes output, 'require "rails-xz-bridge"'
  end

  def test_defaults_the_library_to_the_stem_plus_platform_suffix
    output = generate("extern func noop()\n")

    assert_includes output, "xz_library \"libcurl#{RailsXz::Bridge::Generator::PLATFORM_SUFFIX}\""
  end

  def test_explicit_library_and_module_name_win
    output = generate("extern func noop()\n", lib: "libcurl.so.4", module_name: "Acme::Curl")

    assert_includes output, "xz_library \"libcurl.so.4\""
    assert_includes output, "module Acme::Curl"
  end

  def test_emits_cstruct_and_function_declarations
    output = generate(LIBRARY)

    assert_includes output, "xz_cstruct :curl_slist, { data: :str, next: :ptr }"
    assert_includes output, "xz_func :curl_easy_init, {}, :ptr"
    assert_includes output,
                    "xz_func :curl_easy_setopt, { handle: :ptr, option: :int, param: :ptr }, :int"
    assert_includes output, "xz_func :curl_easy_cleanup, { handle: :ptr }, :unit"
  end

  def test_emits_mut_parameters_with_a_prefixed_symbol
    output = generate("extern func parse_amount(text: Str, mut out: Float) -> Int\n")

    assert_includes output, "xz_func :parse_amount, { text: :str, out: :mut_float }, :int"
  end

  def test_emits_nested_cstructs_in_dependency_order
    output = generate(<<~XZINT)
      @cstruct record Outer {
          inner: Inner
      }
      @cstruct record Inner {
          value: Int
      }
    XZINT

    assert_operator output.index("xz_cstruct :Inner"), :<, output.index("xz_cstruct :Outer")
  end

  def test_non_c_representable_return_is_a_hard_error
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func find(a: Int) -> Result[Int, Err]\n")
    end

    assert_match(/not C-representable/, error.message)
  end

  def test_unit_parameter_is_rejected
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func noop(u: Unit)\n")
    end

    assert_match(/Unit is allowed only as a return/, error.message)
  end

  def test_unknown_type_is_rejected
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func noop(value: Nope)\n")
    end

    assert_match(/unknown type 'Nope'/, error.message)
  end

  def test_cyclic_cstruct_is_rejected
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate(<<~XZINT)
        @cstruct record A { b: B }
        @cstruct record B { a: A }
      XZINT
    end

    assert_match(/nests itself|cyclic/, error.message)
  end

  def test_generic_extern_is_rejected
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func first[T](value: T) -> T\n")
    end

    assert_match(/generic/, error.message)
  end

  def test_escapes_the_library_name
    output = generate("extern func noop()\n", lib: "weird\"lib.so")

    assert_includes output, "xz_library \"weird\\\"lib.so\""
  end

  def test_generated_source_evaluates_to_a_facade_module
    output = generate("extern func add(a: Int, b: Int) -> Int\n", module_name: "GeneratedBinding")

    namespace = Module.new
    namespace.module_eval(output)
    binding = namespace.const_get(:GeneratedBinding)

    assert binding.declared_functions.key?(:add)
    assert_equal({ a: :int, b: :int }, binding.declared_functions.fetch(:add)[:params])
    assert_equal :int, binding.declared_functions.fetch(:add)[:returns]
  end
end