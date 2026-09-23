# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# Builds an Xz shared library whose @export signatures cross by-value aggregates
# (Str/Bytes/@cstruct) and calls it through the ffi backend. Skipped unless
# XZ_BIN points at the Xz language CLI, so the unit suite still runs without the
# compiler.
class AggregateLibraryTest < Minitest::Test
  SOURCE = <<~XZ
    @cstruct record Point {
        x: Int
        y: Int
    }

    /// Returns the character count of s.
    /// @intent  Returns the character count of s.
    /// @effects none
    @export func str_len(s: Str) -> Int {
        s.len()
    }

    /// Returns s in upper case.
    /// @intent  Returns s in upper case.
    /// @effects none
    @export func str_upper(s: Str) -> Str {
        s.to_upper()
    }

    /// Returns the byte count of b.
    /// @intent  Returns the byte count of b.
    /// @effects none
    @export func bytes_len(b: Bytes) -> usize {
        b.len() as usize
    }

    /// Sums a point's components.
    /// @intent  Returns p.x + p.y.
    /// @effects none
    @export func point_sum(p: Point) -> Int {
        p.x + p.y
    }

    /// Builds a point.
    /// @intent  Returns a Point with the given components.
    /// @effects none
    @export func make_point(x: Int, y: Int) -> Point {
        Point(x, y)
    }

    /// Multiplies value in place and returns the result.
    /// @intent  Multiplies value in place and returns the result.
    /// @effects mut
    @export func scale(mut value: Float, factor: Float) -> Float {
        value = value * factor
        value
    }

    /// Increments the integer in place and returns the new value.
    /// @intent  Increments the integer in place.
    /// @effects mut
    @export func bump(mut n: Int) -> Int {
        n = n + 1
        n
    }

    func main() {
        print("aggregate\\n")
    }
  XZ

  def setup
    skip "XZ_BIN is not set; skipping the shared-library test" unless RailsXz::Toolchain.configured?
  end

  def test_builds_and_calls_by_value_exports
    Dir.mktmpdir("rails-xz-aggregate") do |dir|
      lib = File.join(dir, "libaggregate.so")
      build!(dir, lib)

      mod = binding_module(lib)

      assert_equal 5, mod.str_len("hello")
      assert_equal "HELLO", mod.str_upper("hello")
      assert_equal 3, mod.bytes_len("\x00\x01\x02".b)
      assert_equal 7, mod.point_sum(mod::Point.new(x: 3, y: 4))
      assert_equal mod::Point.new(x: 5, y: 6), mod.make_point(5, 6)
    end
  end

  def test_builds_and_calls_mut_cells
    Dir.mktmpdir("rails-xz-aggregate") do |dir|
      lib = File.join(dir, "libaggregate.so")
      build!(dir, lib)

      mod = binding_module(lib)

      value, out = mod.scale(2.0, 3.0)
      assert_in_delta 6.0, value, 1e-9
      assert_in_delta 6.0, out[:value], 1e-9

      value, out = mod.bump(41)
      assert_equal 42, value
      assert_equal({ n: 42 }, out)
    end
  end

  private

  def binding_module(lib)
    Module.new do
      extend RailsXz::Bridge::Facade
      xz_library lib
      xz_cstruct :Point, { x: :int, y: :int }
      xz_func :str_len, { s: :str }, :int
      xz_func :str_upper, { s: :str }, :str
      xz_func :bytes_len, { b: :bytes }, :int
      xz_func :point_sum, { p: :Point }, :int
      xz_func :make_point, { x: :int, y: :int }, :Point
      xz_func :scale, { value: :mut_float, factor: :float }, :float
      xz_func :bump, { n: :mut_int }, :int
    end
  end

  def build!(dir, lib)
    source = File.join(dir, "aggregate.xz")
    File.write(source, SOURCE)
    out, err, status = Open3.capture3(
      RailsXz::Toolchain.xz_bin, "build", "--shared", "--out", lib, source
    )

    assert status.success?, "xz build --shared failed: #{err}#{out}"
    assert File.exist?(lib), "expected #{lib} to be written"
  end
end
