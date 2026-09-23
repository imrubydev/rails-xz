# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Verifies the GVL release policy from docs/01-bridge.md section 7: the GVL is
# released unless the compiler proved the function pure (`@effects none`). A
# native call that busy-waits lets another Ruby thread run only if the GVL was
# released, so the other thread's progress is the observable.
class GvlPolicyTest < Minitest::Test
  STUB_C = <<~C
    #include <stdint.h>
    #include <stddef.h>
    #include <time.h>
    typedef struct XzStr { const char* ptr; size_t len; } XzStr;

    static void wait_ms(int64_t ms) {
        struct timespec start, now;
        clock_gettime(CLOCK_MONOTONIC, &start);
        long long target = (long long)ms * 1000000LL;
        do { clock_gettime(CLOCK_MONOTONIC, &now); }
        while (((now.tv_sec - start.tv_sec) * 1000000000LL +
                (now.tv_nsec - start.tv_nsec)) < target);
    }

    int64_t busy_wait_ms(int64_t ms) { wait_ms(ms); return ms; }

    int64_t str_busy(XzStr s, int64_t ms) {
        wait_ms(ms);
        return (int64_t)s.len;
    }
  C

  WAIT_MS = 200

  def test_pure_fiddle_call_holds_the_gvl
    with_library do |so|
      mod = binding_module(so)
      mod.xz_func :busy_wait_ms, { ms: :int }, :int, effects: [:none]

      assert_operator gvl_iterations { |ms| mod.busy_wait_ms(ms) }, :<, 5_000
    end
  end

  def test_io_fiddle_call_releases_the_gvl
    with_library do |so|
      mod = binding_module(so)
      mod.xz_func :busy_wait_ms, { ms: :int }, :int, effects: [:io]

      assert_operator gvl_iterations { |ms| mod.busy_wait_ms(ms) }, :>, 20_000
    end
  end

  def test_unknown_profile_releases_the_gvl
    with_library do |so|
      mod = binding_module(so)
      mod.xz_func :busy_wait_ms, { ms: :int }, :int

      assert_operator gvl_iterations { |ms| mod.busy_wait_ms(ms) }, :>, 20_000
    end
  end

  def test_release_gvl_mark_forces_release_for_a_pure_function
    with_library do |so|
      mod = binding_module(so)
      mod.xz_func :busy_wait_ms, { ms: :int }, :int, effects: [:none], release_gvl: true

      assert_operator gvl_iterations { |ms| mod.busy_wait_ms(ms) }, :>, 20_000
    end
  end

  def test_pure_ffi_call_holds_the_gvl
    with_library do |so|
      mod = binding_module(so)
      mod.xz_func :str_busy, { s: :str, ms: :int }, :int, effects: [:none]

      assert_operator gvl_iterations { |ms| mod.str_busy("hello", ms) }, :<, 5_000
    end
  end

  def test_io_ffi_call_releases_the_gvl
    with_library do |so|
      mod = binding_module(so)
      mod.xz_func :str_busy, { s: :str, ms: :int }, :int, effects: [:io]

      assert_operator gvl_iterations { |ms| mod.str_busy("hello", ms) }, :>, 20_000
    end
  end

  private

  # Warms up once (the first call builds the loader or the ffi marshaller, which
  # is unrelated to the policy), then counts how many times a second Ruby thread
  # advances while the native call runs.
  def gvl_iterations
    yield 1

    counter = 0
    running = true
    thread = Thread.new { counter += 1 while running }
    sleep 0.02
    before = counter
    yield WAIT_MS
    after = counter
    running = false
    thread.join
    after - before
  end

  def binding_module(so)
    Module.new do
      extend RailsXz::Bridge::Facade
      xz_library so
    end
  end

  def with_library
    skip "cc is not available" unless system("cc --version > /dev/null 2>&1")

    Dir.mktmpdir("rails-xz-gvl") do |dir|
      source = File.join(dir, "stub.c")
      so = File.join(dir, "libstub.so")
      File.write(source, STUB_C)
      unless system("cc", "-shared", "-fPIC", "-o", so, source)
        skip "cc failed to build the stub library"
      end

      yield so
    end
  end
end
