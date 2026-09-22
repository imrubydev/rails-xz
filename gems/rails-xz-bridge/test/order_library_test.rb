# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# Phase 1 PoC (docs/05-roadmap.md): build examples/order.xz with
# `xz build --shared` and call the exported payable_total through the Fiddle
# loader. Skipped unless XZ_BIN points at the Xz language CLI, so the unit
# suite still runs on a machine without the compiler.
class OrderLibraryTest < Minitest::Test
  EXAMPLE = File.expand_path("../../../examples/order.xz", __dir__)

  def setup
    skip "XZ_BIN is not set; skipping the shared-library PoC" unless RailsXz::Toolchain.configured?
  end

  def test_builds_and_calls_payable_total
    Dir.mktmpdir("rails-xz-poc") do |dir|
      lib = File.join(dir, "liborder.so")
      build!(lib)

      assert_match(
        /double payable_total\(double subtotal, double tax_rate\);/,
        File.read(File.join(dir, "liborder.h"))
      )

      loader = RailsXz::Bridge::Loader.new(lib)
      loader.load!
      payable = loader.function(
        "payable_total",
        [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE],
        Fiddle::TYPE_DOUBLE
      )

      assert_in_delta 110.0, payable.call(100.0, 0.1), 1e-9
      assert_in_delta 200.0, payable.call(200.0, 0.0), 1e-9
    end
  end

  private

  def build!(lib)
    xz = RailsXz::Toolchain.xz_bin
    out, err, status = Open3.capture3(xz, "build", "--shared", "--out", lib, EXAMPLE)

    assert status.success?, "xz build --shared failed: #{err}#{out}"
    assert File.exist?(lib), "expected #{lib} to be written"
  end
end