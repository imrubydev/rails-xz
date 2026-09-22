# frozen_string_literal: true

require "test_helper"

class CheckJsonTest < Minitest::Test
  SAMPLE = <<~JSON
    [
      {
        "version": 1,
        "severity": "error",
        "code": "I0020",
        "message": "declared @effects 'none' does not match derived effects 'io'",
        "category": "intent",
        "span": { "file": "app/xz/order.xz", "start": [4, 6], "end": [4, 7] },
        "suggestion": { "fix": "extend @effects", "confidence": 0.9 }
      }
    ]
  JSON

  def test_missing_compiler_raises
    original = ENV["XZ_BIN"]
    ENV["XZ_BIN"] = nil
    checker = RailsXz::Agent::CheckJson.new

    assert_raises(RailsXz::Toolchain::MissingCompiler) do
      checker.call("app/xz/order.xz")
    end
  ensure
    ENV["XZ_BIN"] = original
  end

  def test_parse_builds_diagnostics
    checker = RailsXz::Agent::CheckJson.new(xz_bin: "/bin/true")
    status = Struct.new(:exitstatus).new(1)

    result = checker.parse(SAMPLE, "", status)
    diagnostic = result[:diagnostics].first

    assert_equal "I0020", diagnostic.code
    assert_equal 4, diagnostic.line
    assert_equal 0.9, diagnostic.confidence
    assert diagnostic.error?
  end

  def test_invalid_json_raises
    checker = RailsXz::Agent::CheckJson.new(xz_bin: "/bin/true")
    status = Struct.new(:exitstatus).new(1)

    assert_raises(RailsXz::Agent::DiagnosticsParseError) do
      checker.parse("not json", "", status)
    end
  end
end