# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Exercises the ffi backend end to end against a real C library that mirrors the
# Xz C ABI for by-value aggregates (XzStr, XzBytes, @cstruct). The stub is
# compiled locally so the suite runs without XZ_BIN.
class FfiMarshallingTest < Minitest::Test
  STUB_C = <<~C
    #include <stdint.h>
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdlib.h>

    typedef struct XzStr { const char* ptr; size_t len; } XzStr;
    typedef struct XzBytes { const uint8_t* ptr; size_t len; } XzBytes;
    typedef struct Point { int64_t x; int64_t y; } Point;
    typedef struct Rect { Point tl; Point br; } Rect;
    typedef struct Named { XzStr name; int64_t id; } Named;

    int64_t str_len(XzStr s) { return (int64_t)s.len; }

    XzStr str_upper(XzStr s) {
      char *b = (char*)malloc(s.len);
      for (size_t i = 0; i < s.len; i++) {
        char c = s.ptr[i];
        b[i] = (c >= 'a' && c <= 'z') ? c - 32 : c;
      }
      XzStr o = { b, s.len };
      return o;
    }

    int64_t bytes_len(XzBytes b) { return (int64_t)b.len; }
    XzBytes bytes_echo(XzBytes b) { return b; }

    Point make_point(int64_t x, int64_t y) { Point p = { x, y }; return p; }
    int64_t point_sum(Point p) { return p.x + p.y; }
    Point point_add(Point a, Point b) { Point p = { a.x + b.x, a.y + b.y }; return p; }

    int64_t rect_area(Rect r) { return (r.br.x - r.tl.x) * (r.br.y - r.tl.y); }
    Rect make_rect(int64_t x1, int64_t y1, int64_t x2, int64_t y2) {
      Rect r = { { x1, y1 }, { x2, y2 } };
      return r;
    }

    int64_t named_len(Named n) { return n.id + (int64_t)n.name.len; }
    Named make_named(XzStr name, int64_t id) { Named n = { name, id }; return n; }

    void* ptr_roundtrip(void* p) { return p; }
    bool ptr_is_null(void* p) { return p == 0; }
    int64_t ptr_tag(XzStr s, void* p) { return (int64_t)s.len + (p == 0 ? 0 : 1000); }
    void* ptr_echo(XzStr s, void* p) { (void)s; return p; }

    int64_t bump(int64_t* n) { *n += 1; return *n; }
    double scale(double* v, double factor) { *v *= factor; return *v; }
    bool toggle(bool* b) { *b = !*b; return *b; }
    char next_char_ptr(char* c) { *c += 1; return *c; }
    void bump_point(Point* p) { p->x += 1; p->y += 1; }
    int64_t str_len_out(XzStr* s) { return (int64_t)s->len; }
    int64_t ptr_write(void** p) { *p = (void*)0x1234; return 0; }
  C

  def test_str_parameter_and_return
    with_library do |mod|
      mod.xz_func(:str_len, { s: :str }, :int)
      mod.xz_func(:str_upper, { s: :str }, :str)

      assert_equal 5, mod.str_len("hello")
      assert_equal "HELLO", mod.str_upper("hello")
    end
  end

  def test_str_rejects_a_non_string
    with_library do |mod|
      mod.xz_func(:str_len, { s: :str }, :int)

      error = assert_raises(RailsXz::Bridge::MarshallError) { mod.str_len(42) }
      assert_match(/Str expects a String/, error.message)
    end
  end

  def test_bytes_parameter_and_return
    with_library do |mod|
      mod.xz_func(:bytes_len, { b: :bytes }, :int)
      mod.xz_func(:bytes_echo, { b: :bytes }, :bytes)

      raw = "\x00\x01\x02".b
      assert_equal 3, mod.bytes_len(raw)
      assert_equal raw, mod.bytes_echo(raw)
      assert_equal Encoding::BINARY, mod.bytes_echo(raw).encoding
    end
  end

  def test_cstruct_by_value_parameter_and_return
    with_library do |mod|
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_func(:make_point, { x: :int, y: :int }, :Point)
      mod.xz_func(:point_sum, { p: :Point }, :int)
      mod.xz_func(:point_add, { a: :Point, b: :Point }, :Point)

      assert_equal 7, mod.point_sum(mod::Point.new(x: 3, y: 4))

      sum = mod.point_add(mod::Point.new(x: 1, y: 2), mod::Point.new(x: 10, y: 20))
      assert_equal mod::Point.new(x: 11, y: 22), sum
      assert_equal mod::Point.new(x: 5, y: 6), mod.make_point(5, 6)
    end
  end

  def test_nested_cstruct_by_value
    with_library do |mod|
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_cstruct(:Rect, { tl: :Point, br: :Point })
      mod.xz_func(:rect_area, { r: :Rect }, :int)
      mod.xz_func(:make_rect, { x1: :int, y1: :int, x2: :int, y2: :int }, :Rect)

      rect = mod.make_rect(1, 2, 4, 6)
      assert_equal mod::Point.new(x: 1, y: 2), rect.tl
      assert_equal mod::Point.new(x: 4, y: 6), rect.br
      assert_equal 12, mod.rect_area(rect)
    end
  end

  def test_cstruct_with_a_str_field
    with_library do |mod|
      mod.xz_cstruct(:Named, { name: :str, id: :int })
      mod.xz_func(:named_len, { n: :Named }, :int)
      mod.xz_func(:make_named, { name: :str, id: :int }, :Named)

      assert_equal 8, mod.named_len(mod::Named.new(name: "hello", id: 3))

      named = mod.make_named("hi", 7)
      assert_equal "hi", named.name
      assert_equal 7, named.id
    end
  end

  def test_cstruct_rejects_a_value_without_the_fields
    with_library do |mod|
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_func(:point_sum, { p: :Point }, :int)

      error = assert_raises(RailsXz::Bridge::MarshallError) { mod.point_sum(Object.new) }
      assert_match(/has no field 'x'/, error.message)
    end
  end

  def test_xz_shared_binding_refuses_a_by_value_struct_over_16_bytes
    with_library do |mod|
      mod.xz_abi :xz_shared
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_cstruct(:Rect, { tl: :Point, br: :Point })
      mod.xz_func(:rect_area, { r: :Rect }, :int)

      rect = mod::Rect.new(tl: mod::Point.new(x: 1, y: 2), br: mod::Point.new(x: 4, y: 6))
      error = assert_raises(RailsXz::Bridge::MarshallError) { mod.rect_area(rect) }
      assert_match(/Rect is 32 bytes/, error.message)
      assert_match(/shared ABI/, error.message)
    end
  end

  def test_xz_shared_binding_refuses_a_large_by_value_return
    with_library do |mod|
      mod.xz_abi :xz_shared
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_cstruct(:Rect, { tl: :Point, br: :Point })
      mod.xz_func(:make_rect, { x1: :int, y1: :int, x2: :int, y2: :int }, :Rect)

      error = assert_raises(RailsXz::Bridge::MarshallError) { mod.make_rect(1, 2, 4, 6) }
      assert_match(/Rect is 32 bytes/, error.message)
    end
  end

  def test_xz_shared_binding_still_passes_a_register_class_struct
    with_library do |mod|
      mod.xz_abi :xz_shared
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_func(:point_sum, { p: :Point }, :int)

      assert_equal 7, mod.point_sum(mod::Point.new(x: 3, y: 4))
    end
  end

  def test_a_foreign_binding_is_not_guarded_for_a_large_struct
    with_library do |mod|
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_cstruct(:Rect, { tl: :Point, br: :Point })
      mod.xz_func(:rect_area, { r: :Rect }, :int)

      rect = mod::Rect.new(tl: mod::Point.new(x: 1, y: 2), br: mod::Point.new(x: 4, y: 6))
      assert_equal 12, mod.rect_area(rect)
    end
  end

  def test_ptr_round_trips_as_a_handle
    with_library do |mod|
      mod.xz_func(:ptr_roundtrip, { p: :ptr }, :ptr)
      mod.xz_func(:ptr_is_null, { p: :ptr }, :bool)

      handle = RailsXz::Bridge::Handle.new(0x1234)
      assert_equal handle, mod.ptr_roundtrip(handle)
      assert_equal false, mod.ptr_is_null(handle)
      assert_equal true, mod.ptr_is_null(nil)
    end
  end

  def test_ptr_on_the_ffi_path
    with_library do |mod|
      mod.xz_func(:ptr_tag, { s: :str, p: :ptr }, :int)
      mod.xz_func(:ptr_echo, { s: :str, p: :ptr }, :ptr)

      handle = RailsXz::Bridge::Handle.new(0x99)
      assert_equal 2, mod.ptr_tag("hi", nil)
      assert_equal 1002, mod.ptr_tag("hi", handle)
      assert_equal handle, mod.ptr_echo("hi", handle)
      assert_equal 0, mod.ptr_echo("hi", nil).to_i
    end
  end

  def test_mut_scalar_returns_the_value_and_an_out_hash
    with_library do |mod|
      mod.xz_func(:bump, { n: :mut_int }, :int)
      mod.xz_func(:scale, { v: :mut_float, factor: :float }, :float)
      mod.xz_func(:toggle, { b: :mut_bool }, :bool)
      mod.xz_func(:next_char_ptr, { c: :mut_char }, :char)

      value, out = mod.bump(41)
      assert_equal 42, value
      assert_equal({ n: 42 }, out)

      value, out = mod.scale(2.0, 3.0)
      assert_in_delta 6.0, value, 1e-9
      assert_in_delta 6.0, out[:v], 1e-9

      value, out = mod.toggle(false)
      assert_equal true, value
      assert_equal({ b: true }, out)

      value, out = mod.next_char_ptr("a")
      assert_equal "b", value
      assert_equal({ c: "b" }, out)
    end
  end

  def test_mut_cstruct_cell
    with_library do |mod|
      mod.xz_cstruct(:Point, { x: :int, y: :int })
      mod.xz_func(:bump_point, { p: :mut_Point }, :unit)

      value, out = mod.bump_point(mod::Point.new(x: 1, y: 2))
      assert_nil value
      assert_equal mod::Point.new(x: 2, y: 3), out[:p]
    end
  end

  def test_mut_str_cell
    with_library do |mod|
      mod.xz_func(:str_len_out, { s: :mut_str }, :int)

      value, out = mod.str_len_out("hello")
      assert_equal 5, value
      assert_equal({ s: "hello" }, out)
    end
  end

  def test_mut_ptr_cell
    with_library do |mod|
      mod.xz_func(:ptr_write, { p: :mut_ptr }, :int)

      value, out = mod.ptr_write(RailsXz::Bridge::Handle.new(0x99))
      assert_equal 0, value
      assert_equal 0x1234, out[:p].to_i
    end
  end

  def test_a_signature_without_mut_returns_a_single_value
    with_library do |mod|
      mod.xz_func(:str_len, { s: :str }, :int)

      assert_equal 5, mod.str_len("hello")
    end
  end

  private

  def with_library
    skip "cc is not available" unless system("cc --version > /dev/null 2>&1")

    Dir.mktmpdir("rails-xz-ffi") do |dir|
      source = File.join(dir, "stub.c")
      so = File.join(dir, "libstub.so")
      File.write(source, STUB_C)
      skip "cc failed to build the stub library" unless system("cc", "-shared", "-fPIC", "-o", so, source)

      yield binding_module(so)
    end
  end

  def binding_module(so)
    Module.new do
      extend RailsXz::Bridge::Facade
      xz_library so
    end
  end
end
