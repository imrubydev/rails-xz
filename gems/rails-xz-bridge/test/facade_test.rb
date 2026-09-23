# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class FacadeTest < Minitest::Test
  STUB_C = <<~C
    #include <stdint.h>
    #include <stdbool.h>
    #include <stddef.h>
    int64_t add(int64_t a, int64_t b) { return a + b; }
    double scale(double x, double factor) { return x * factor; }
    bool truthy(int64_t x) { return x != 0; }
    char next_char(char c) { return c + 1; }
    void* ptr_roundtrip(void* p) { return p; }
    bool ptr_is_null(void* p) { return p == 0; }
  C

  def binding_module
    Module.new do
      extend RailsXz::Bridge::Facade
    end
  end

  def test_xz_cstruct_defines_a_data_class_with_field_order
    mod = binding_module
    mod.xz_cstruct(:Color, { r: :usize, g: :usize, b: :usize, a: :usize })

    color = mod.const_get(:Color)
    assert_kind_of Class, color
    assert_equal %i[r g b a], color.members
    assert_equal({ r: :usize, g: :usize, b: :usize, a: :usize }, mod.declared_cstructs[:Color])
  end

  def test_xz_func_defines_a_singleton_method_and_records_the_signature
    mod = binding_module
    mod.xz_func(:add, { a: :int, b: :int }, :int)

    assert_respond_to mod, :add
    assert_equal({ a: :int, b: :int }, mod.declared_functions.dig(:add, :params))
    assert_equal :int, mod.declared_functions.dig(:add, :returns)
  end

  def test_str_parameter_routes_to_the_ffi_backend
    mod = binding_module
    mod.xz_func(:greet, { name: :str }, :unit)

    # Fiddle would reject ':str' before loading; the load attempt proves the
    # aggregate signature took the ffi path.
    error = assert_raises(RailsXz::Bridge::MarshallError) { mod.greet("x") }
    assert_match(/no xz_library declared/, error.message)
  end

  def test_mut_parameters_fail_loudly
    mod = binding_module
    mod.xz_func(:bump, { out: :mut_int }, :int)

    error = assert_raises(RailsXz::Bridge::MarshallError) { mod.bump(1) }
    assert_match(/mut_int/, error.message)
  end

  def test_ptr_parameters_reject_a_bare_integer
    mod = binding_module
    mod.xz_func(:handle, { ptr: :ptr }, :unit)

    error = assert_raises(RailsXz::Bridge::MarshallError) { mod.handle(1) }
    assert_match(/Handle/, error.message)
  end

  def test_wrong_argument_count_is_an_argument_error
    mod = binding_module
    mod.xz_func(:add, { a: :int, b: :int }, :int)

    assert_raises(ArgumentError) { mod.add(1) }
  end

  def test_scalar_calls_round_trip_through_a_real_shared_library
    skip "cc is not available" unless system("cc --version > /dev/null 2>&1")

    Dir.mktmpdir("rails-xz-facade") do |dir|
      so = compile_stub(dir)

      mod = binding_module
      mod.xz_library(so)
      mod.xz_func(:add, { a: :int, b: :int }, :int)
      mod.xz_func(:scale, { x: :float, factor: :float }, :float)
      mod.xz_func(:truthy, { x: :int }, :bool)
      mod.xz_func(:next_char, { c: :char }, :char)

      assert_equal 5, mod.add(2, 3)
      assert_in_delta 6.0, mod.scale(1.5, 4.0), 1e-9
      assert_equal false, mod.truthy(0)
      assert_equal true, mod.truthy(7)
      assert_equal "b", mod.next_char("a")
    end
  end

  def test_ptr_round_trips_as_an_opaque_handle
    skip "cc is not available" unless system("cc --version > /dev/null 2>&1")

    Dir.mktmpdir("rails-xz-facade") do |dir|
      so = compile_stub(dir)

      mod = binding_module
      mod.xz_library(so)
      mod.xz_func(:ptr_roundtrip, { p: :ptr }, :ptr)
      mod.xz_func(:ptr_is_null, { p: :ptr }, :bool)

      handle = RailsXz::Bridge::Handle.new(0x1234)
      result = mod.ptr_roundtrip(handle)

      assert_kind_of RailsXz::Bridge::Handle, result
      assert_equal 0x1234, result.to_i
      assert_equal false, mod.ptr_is_null(handle)
      assert_equal true, mod.ptr_is_null(nil)
    end
  end

  private

  def compile_stub(dir)
    source = File.join(dir, "stub.c")
    so = File.join(dir, "libstub.so")
    File.write(source, STUB_C)
    success = system("cc", "-shared", "-fPIC", "-o", so, source)
    skip "cc failed to build the stub library" unless success

    so
  end
end