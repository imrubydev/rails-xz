# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Exercises `transfer` ownership end to end: the `.xzint` parser and generator
# carry the `transfer`/`release` clauses into the binding, and the runtime honors
# them against a real C library. The stub is compiled locally so the suite runs
# without XZ_BIN. See docs/01-bridge.md section 4.6.
class OwnershipTest < Minitest::Test
  STUB_C = <<~C
    #include <stdint.h>
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdlib.h>
    #include <string.h>

    typedef struct XzStr { const char* ptr; size_t len; } XzStr;
    typedef struct XzBytes { const uint8_t* ptr; size_t len; } XzBytes;

    static int64_t releases = 0;
    static char* kept = 0;
    static size_t kept_len = 0;

    XzStr make_str(void) {
      char* b = (char*)malloc(6);
      memcpy(b, "hello", 5);
      b[5] = 0;
      XzStr s = { b, 5 };
      return s;
    }
    XzBytes make_bytes(void) {
      uint8_t* b = (uint8_t*)malloc(3);
      b[0] = 1; b[1] = 2; b[2] = 3;
      XzBytes s = { b, 3 };
      return s;
    }
    void str_free(void* p) { free(p); releases++; }
    void bytes_free(void* p) { free(p); releases++; }

    XzStr borrow_str(void) {
      XzStr s = { "borrowed", 8 };
      return s;
    }

    void* make_ptr(void) {
      int64_t* p = (int64_t*)malloc(sizeof(int64_t));
      *p = 0x2a;
      return p;
    }
    void ptr_free(void* p) { free(p); releases++; }
    int64_t take_ptr(void* p) { if (p) { free(p); releases++; } return 1; }

    int64_t releases_fn(void) { return releases; }

    int64_t keep_str(XzStr s) { kept = (char*)s.ptr; kept_len = s.len; return (int64_t)s.len; }
    int64_t kept_first(void) { return kept ? (int64_t)(unsigned char)kept[0] : -1; }
    int64_t kept_len_fn(void) { return (int64_t)kept_len; }
  C

  XZINT = <<~XZINT
    @interface foreign
    extern func str_free(ptr: Ptr) -> Unit
    extern func bytes_free(ptr: Ptr) -> Unit
    extern func ptr_free(ptr: Ptr) -> Unit
    extern func make_str() -> transfer Str release str_free
    extern func make_bytes() -> transfer Bytes release bytes_free
    extern func borrow_str() -> Str
    extern func make_ptr() -> transfer Ptr release ptr_free
    extern func take_ptr(transfer p: Ptr) -> Int
    extern func releases_fn() -> Int
    extern func keep_str(transfer data: Str) -> Int
    extern func kept_first() -> Int
    extern func kept_len_fn() -> Int
  XZINT

  def test_a_transfer_str_return_is_copied_and_released
    with_binding do |binding|
      assert_equal "hello", binding.make_str
      assert_equal 1, binding.releases_fn
    end
  end

  def test_a_transfer_bytes_return_is_copied_and_released
    with_binding do |binding|
      value = binding.make_bytes
      assert_equal "\x01\x02\x03".b, value
      assert_equal Encoding::BINARY, value.encoding
      assert_equal 1, binding.releases_fn
    end
  end

  def test_a_borrowed_return_is_not_released
    with_binding do |binding|
      assert_equal "borrowed", binding.borrow_str
      assert_equal 0, binding.releases_fn
    end
  end

  def test_a_transfer_ptr_return_owns_its_release
    with_binding do |binding|
      handle = binding.make_ptr
      assert_kind_of RailsXz::Bridge::Handle, handle
      assert_equal 0, binding.releases_fn

      handle.release!
      assert_equal 1, binding.releases_fn
      refute_equal 0, handle.to_i

      handle.release! # idempotent: never freed twice
      assert_equal 1, binding.releases_fn
    end
  end

  def test_a_transfer_ptr_parameter_consumes_the_handle
    with_binding do |binding|
      handle = binding.make_ptr

      assert_equal 1, binding.take_ptr(handle)
      assert handle.consumed?
      assert_equal 1, binding.releases_fn

      error = assert_raises(RailsXz::Bridge::MarshallError) { binding.take_ptr(handle) }
      assert_match(/already transferred/, error.message)
    end
  end

  def test_a_transfer_str_parameter_survives_ruby_gc
    with_binding do |binding|
      assert_equal 5, binding.keep_str("hello")
      GC.start
      assert_equal "h".ord, binding.kept_first
      assert_equal 5, binding.kept_len_fn
    end
  end

  def test_a_borrowed_handle_cannot_be_released
    with_binding do |binding|
      handle = RailsXz::Bridge::Handle.new(0x1234)

      error = assert_raises(RailsXz::Bridge::MarshallError) { handle.release! }
      assert_match(/borrowed/, error.message)
    end
  end

  private

  def with_binding
    skip "cc is not available" unless system("cc --version > /dev/null 2>&1")

    Dir.mktmpdir("rails-xz-ownership") do |dir|
      source = File.join(dir, "stub.c")
      so = File.join(dir, "libstub.so")
      File.write(source, STUB_C)
      skip "cc failed to build the stub library" unless system("cc", "-shared", "-fPIC", "-o", so, source)

      code = RailsXz::Bridge::Generator
             .new("stub.xzint", source: XZINT, lib: so, module_name: "OwnershipBinding")
             .generate
      namespace = Module.new
      namespace.module_eval(code)
      yield namespace.const_get(:OwnershipBinding)
    end
  end
end
