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
