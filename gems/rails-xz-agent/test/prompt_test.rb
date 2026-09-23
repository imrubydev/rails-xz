# frozen_string_literal: true

require "test_helper"

class PromptTest < Minitest::Test
  def diagnostic(code:, message:, severity: "error", category: "intent", line: 4,
                 fix: nil, confidence: 0.9)
    RailsXz::Agent::Diagnostic.from_json(
      "severity" => severity,
      "code" => code,
      "message" => message,
      "category" => category,
      "span" => { "start" => [line, 0], "end" => [line, 1] },
      "suggestion" => fix && { "fix" => fix, "confidence" => confidence }
    )
  end

  def test_initial_prompt_carries_the_intent_target_and_shell
    prompt = RailsXz::Agent::Prompt.new(
      intent: "Compute the payable total.",
      target: "app/xz/order.xz",
      shell: "/// @intent ..."
    )

    text = prompt.initial

    assert_includes text, "Compute the payable total."
    assert_includes text, "app/xz/order.xz"
    assert_includes text, "/// @intent ..."
    assert_includes text, "I0020"
  end

  def test_initial_prompt_marks_a_missing_shell
    prompt = RailsXz::Agent::Prompt.new(intent: "x", target: "app/xz/x.xz")

    assert_includes prompt.initial, "(none)"
  end

  def test_repair_prompt_includes_the_previous_candidate_and_diagnostics
    prompt = RailsXz::Agent::Prompt.new(intent: "x", target: "app/xz/x.xz")
    diagnostics = [
      diagnostic(code: "I0020", message: "effects mismatch", fix: "add io")
    ]

    text = prompt.repair(source: "func f() {}", diagnostics: diagnostics,
                         attempt: 2, max_attempts: 3)

    assert_includes text, "func f() {}"
    assert_includes text, "[I0020]"
    assert_includes text, "effects mismatch"
    assert_includes text, "fix: add io"
    assert_includes text, "attempt 2 of 3"
  end

  def test_repair_prompt_ranks_errors_before_warnings
    prompt = RailsXz::Agent::Prompt.new(intent: "x", target: "app/xz/x.xz")
    warning = diagnostic(code: "W0001", message: "warning", severity: "warning")
    error = diagnostic(code: "I0020", message: "fatal")

    text = prompt.repair(source: "f", diagnostics: [warning, error],
                         attempt: 1, max_attempts: 3)

    assert_operator text.index("[I0020]"), :<, text.index("[W0001]")
  end
end
