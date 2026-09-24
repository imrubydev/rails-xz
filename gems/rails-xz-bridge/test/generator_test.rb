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
    source = "@interface foreign\n#{source}" unless source.start_with?("@interface")
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

  def test_emits_the_effect_profile_when_given
    output = generate("extern func add(a: Int, b: Int) -> Int\n", effects: { add: [:none] })

    assert_includes output, "xz_func :add, { a: :int, b: :int }, :int, effects: [:none]"
  end

  def test_emits_nothing_for_a_function_without_a_profile
    output = generate("extern func add(a: Int, b: Int) -> Int\n")

    assert_includes output, "xz_func :add, { a: :int, b: :int }, :int"
    refute_includes output, "effects:"
  end

  def test_rejects_an_unknown_effect_label
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func add(a: Int, b: Int) -> Int\n", effects: { add: [:network] })
    end

    assert_match(/unknown effect/, error.message)
  end

  def test_rejects_none_combined_with_another_effect
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func add(a: Int, b: Int) -> Int\n", effects: { add: %i[none io] })
    end

    assert_match(/cannot be combined/, error.message)
  end

  def test_effect_profile_reaches_the_declared_function
    output = generate("extern func add(a: Int, b: Int) -> Int\n",
                      module_name: "EffectBinding", effects: { add: [:io] })

    namespace = Module.new
    namespace.module_eval(output)
    binding = namespace.const_get(:EffectBinding)

    assert_equal [:io], binding.declared_functions.fetch(:add)[:effects]
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

  HEADER = <<~HEADER
    typedef struct XzStr { const char* ptr; size_t len; } XzStr;
    typedef struct Point {
        int64_t x;
        int64_t y;
    } Point;

    Point echo_point(Point p, XzStr label, void* handle);
    int64_t scale(double value, double* out);
  HEADER

  def test_reads_a_generated_header_path
    output = RailsXz::Bridge::Generator
             .new("librich.h", source: HEADER, module_name: "Xz::Bindings::Rich")
             .generate

    assert_includes output, "xz_cstruct :Point, { x: :int, y: :int }"
    assert_includes output, "xz_func :echo_point, { p: :Point, label: :str, handle: :ptr }, :Point"
    assert_includes output, "xz_func :scale, { value: :float, out: :mut_float }, :int"
  end

  def test_marks_a_generated_header_binding_as_xz_shared
    output = RailsXz::Bridge::Generator
             .new("librich.h", source: HEADER, module_name: "Xz::Bindings::Rich")
             .generate

    assert_includes output, "xz_abi :xz_shared"
  end

  def test_does_not_mark_an_xzint_binding_as_xz_shared
    output = generate("extern func noop()\n")

    refute_includes output, "xz_abi"
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

  def test_emits_a_transfer_parameter
    output = generate("extern func write(transfer data: Bytes) -> Int\n")

    assert_includes output, "# extern func write(transfer data: Bytes) -> Int"
    assert_includes output, "xz_func :write, { data: :bytes }, :int, transfer: [:data]"
  end

  def test_emits_a_transfer_return_and_release
    output = generate(<<~XZINT)
      extern func free(ptr: Ptr) -> Unit
      extern func strdup(s: Str) -> transfer Str release free
    XZINT

    assert_includes output, "# extern func strdup(s: Str) -> transfer Str release free"
    assert_includes output, "xz_func :strdup, { s: :str }, :str, release: :free"
  end

  def test_ownership_metadata_reaches_the_declared_function
    output = generate(<<~XZINT, module_name: "OwnershipBinding")
      extern func free(ptr: Ptr) -> Unit
      extern func strdup(s: Str) -> transfer Str release free
      extern func write(transfer data: Bytes) -> Int
    XZINT

    namespace = Module.new
    namespace.module_eval(output)
    binding = namespace.const_get(:OwnershipBinding)

    assert_equal [:data], binding.declared_functions.fetch(:write)[:transfer]
    assert_equal :free, binding.declared_functions.fetch(:strdup)[:release]
    assert_empty binding.declared_functions.fetch(:free)[:transfer]
  end

  def test_rejects_transfer_on_an_export_interface
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("@interface export\nextern func write(transfer data: Bytes) -> Int\n")
    end

    assert_match(/cannot cross an '@interface export'/, error.message)
  end

  def test_rejects_transfer_of_a_scalar
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func write(transfer n: Int) -> Int\n")
    end

    assert_match(/pointer-carrying/, error.message)
  end

  def test_rejects_a_transfer_return_without_a_release_symbol
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func make() -> transfer Str\n")
    end

    assert_match(/must name its deallocator/, error.message)
  end

  def test_rejects_release_on_a_non_transfer_return
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func free(ptr: Ptr) -> Unit\nextern func make() -> Str release free\n")
    end

    assert_match(/not 'transfer'/, error.message)
  end

  def test_rejects_a_release_symbol_that_is_not_declared
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate("extern func strdup(s: Str) -> transfer Str release nope\n")
    end

    assert_match(/not an 'extern func' declared/, error.message)
  end

  def test_rejects_a_release_symbol_with_the_wrong_signature
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate(<<~XZINT)
        extern func free(n: Int) -> Unit
        extern func strdup(s: Str) -> transfer Str release free
      XZINT
    end

    assert_match(/one borrowed pointer parameter/, error.message)
  end

  def test_rejects_a_transfer_of_a_by_value_cstruct
    error = assert_raises(RailsXz::Bridge::GenerationError) do
      generate(<<~XZINT)
        @cstruct record Buf { ptr: Ptr }
        extern func take(transfer buf: Buf) -> Int
      XZINT
    end

    assert_match(/cannot take ownership of a by-value @cstruct/, error.message)
  end
end