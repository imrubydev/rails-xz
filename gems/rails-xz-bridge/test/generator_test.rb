# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

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

  def test_pins_a_generated_header_with_its_digest
    output = RailsXz::Bridge::Generator
             .new("librich.h", source: HEADER, module_name: "Xz::Bindings::Rich")
             .generate

    assert_includes output, "xz_abi_digest \"#{RailsXz::Bridge::Header.digest(HEADER)}\""
  end

  def test_does_not_pin_an_xzint_interface
    output = generate("extern func noop()\n")

    refute_includes output, "xz_abi_digest"
  end

  def test_pinned_source_evaluates_to_a_facade_module
    output = RailsXz::Bridge::Generator
             .new("librich.h", source: HEADER, module_name: "RichBinding")
             .generate

    namespace = Module.new
    namespace.module_eval(output)
    binding = namespace.const_get(:RichBinding)

    assert_equal RailsXz::Bridge::Header.digest(HEADER), binding.xz_pinned_abi_digest
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

  MODULE = <<~XZ
    /// @intent  Adds two integers.
    /// @effects none
    @export func add(a: Int, b: Int) -> Int
    {
        a + b
    }

    /// @intent  Writes a value through an out-parameter.
    /// @effects mut
    @export func scale(value: Float, mut out: Float) -> Int
    {
        0
    }

    func helper(x: Int) -> Int { x + 1 }

    @cstruct record Point {
        x: Int
        y: Int
    }
  XZ

  def generate_module(source, **options)
    RailsXz::Bridge::Generator
      .new("order.xz", source: source, module_name: "Xz::Bindings::Order", **options)
      .generate
  end

  def test_reads_an_xz_module_path
    output = generate_module(MODULE)

    assert_includes output, "module Xz::Bindings::Order"
    assert_includes output, "xz_cstruct :Point, { x: :int, y: :int }"
    assert_includes output, "xz_func :add, { a: :int, b: :int }, :int, effects: [:none]"
    assert_includes output, "xz_func :scale, { value: :float, out: :mut_float }, :int, effects: [:mut]"
  end

  def test_xz_module_does_not_bind_non_exported_functions
    output = generate_module(MODULE)

    refute_includes output, "xz_func :helper"
  end

  def test_reads_the_effect_profile_from_the_module
    output = generate_module(MODULE, module_name: "ModuleEffectBinding")

    namespace = Module.new
    namespace.module_eval(output)
    binding = namespace.const_get(:ModuleEffectBinding)

    assert_equal [:none], binding.declared_functions.fetch(:add)[:effects]
    assert_equal [:mut], binding.declared_functions.fetch(:scale)[:effects]
  end

  def test_an_explicit_effect_profile_wins_over_the_module
    output = generate_module(MODULE, effects: { add: [:io] })

    assert_includes output, "xz_func :add, { a: :int, b: :int }, :int, effects: [:io]"
  end

  def test_an_xz_module_without_effects_emits_no_profile
    output = generate_module("/// @intent x\n@export func f() -> Int { 0 }\n")

    refute_includes output, "effects:"
  end

  def test_an_xz_module_is_not_abi_pinned
    output = generate_module(MODULE)

    refute_includes output, "xz_abi_digest"
  end

  # End-to-end: an `.xz` module generates a binding and the binding calls the
  # library built from the same module. Skipped unless XZ_BIN is set.
  def test_generates_from_a_real_module_and_calls_the_library
    skip "XZ_BIN is not set; skipping the module end-to-end" unless RailsXz::Toolchain.configured?

    Dir.mktmpdir("rails-xz-source") do |dir|
      source = File.join(dir, "math.xz")
      File.write(source, <<~XZ)
        /// @intent  Adds two integers.
        /// @effects none
        @export func add(a: Int, b: Int) -> Int
        {
            a + b
        }

        /// @intent  Writes a value through an out-parameter.
        /// @effects mut
        @export func bump(value: Float, mut out: Float) -> Int
        {
            out = value
            0
        }
      XZ

      lib = File.join(dir, "libmath.so")
      out, err, status = Open3.capture3(RailsXz::Toolchain.xz_bin,
                                        "build", "--shared", "--out", lib, source)
      assert status.success?, "xz build --shared failed: #{err}#{out}"

      code = RailsXz::Bridge::Generator
             .new(source, lib: lib, module_name: "MathBinding")
             .generate

      namespace = Module.new
      namespace.module_eval(code)
      binding = namespace.const_get(:MathBinding)

      assert_equal 5, binding.add(2, 3)
      status_value, updated = binding.bump(4.0, 0.0)
      assert_equal 0, status_value
      assert_equal({ out: 4.0 }, updated)
    end
  end
end