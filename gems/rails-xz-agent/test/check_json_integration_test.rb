# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Runs CheckJson against the real Xz language CLI. Skipped unless XZ_BIN points
# at it, so the unit suite still runs on a machine without the compiler.
class CheckJsonIntegrationTest < Minitest::Test
  VALID = <<~XZ
    /// @intent  Adds one to x.
    /// @effects none
    func add_one(x: Int) -> Int { x + 1 }
  XZ

  INVALID = <<~XZ
    func add_one(x: Int) -> Int { x + 1 }
  XZ

  def setup
    skip "XZ_BIN is not set; skipping the compiler integration test" \
      unless RailsXz::Toolchain.configured?
  end

  def test_accepts_a_clean_module
    with_source(VALID) do |path|
      result = RailsXz::Agent::CheckJson.new.call(path)

      assert_equal 0, result[:exit_status]
      assert_empty result[:diagnostics]
    end
  end

  def test_reports_a_missing_intent_comment
    with_source(INVALID) do |path|
      result = RailsXz::Agent::CheckJson.new.call(path)

      refute_equal 0, result[:exit_status]
      refute_empty result[:diagnostics]

      diagnostic = result[:diagnostics].first
      assert diagnostic.error?
      assert_equal "I0022", diagnostic.code
      assert_equal "intent", diagnostic.category
      assert_equal path, diagnostic.span["file"]
    end
  end

  def test_strict_still_accepts_a_clean_module
    with_source(VALID) do |path|
      result = RailsXz::Agent::CheckJson.new(strict: true).call(path)

      assert_equal 0, result[:exit_status]
      assert_empty result[:diagnostics]
    end
  end

  private

  def with_source(source)
    Dir.mktmpdir("rails-xz-check") do |dir|
      path = File.join(dir, "candidate.xz")
      File.write(path, source)
      yield path
    end
  end
end
