# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class LoopTest < Minitest::Test
  class ScriptedModel
    attr_reader :prompts

    def initialize(*sources)
      @sources = sources
      @prompts = []
    end

    def generate(prompt)
      @prompts << prompt
      @sources.shift
    end
  end

  # Records every candidate it is asked to check and classifies it with the
  # block, which returns the diagnostics for that source.
  class FakeChecker
    attr_reader :seen

    def initialize(&block)
      @block = block
      @seen = []
    end

    def call(path)
      source = File.read(path)
      @seen << source
      diagnostics = @block.call(source)
      { diagnostics: diagnostics, exit_status: diagnostics.empty? ? 0 : 1, stderr: "" }
    end
  end

  def error(code: "I0020")
    RailsXz::Agent::Diagnostic.from_json(
      "severity" => "error", "code" => code, "message" => "bad",
      "category" => "intent", "span" => nil, "suggestion" => nil
    )
  end

  def warning
    RailsXz::Agent::Diagnostic.from_json(
      "severity" => "warning", "code" => "W0001", "message" => "huh",
      "category" => "intent", "span" => nil, "suggestion" => nil
    )
  end

  def run_loop(model:, checker:, retries: RailsXz::Agent::Loop::DEFAULT_RETRIES)
    RailsXz::Agent::Loop.new(model: model, checker: checker, retries: retries).run(
      intent: "Compute the payable total.", target: "app/xz/order.xz"
    )
  end

  def test_passes_on_the_first_clean_candidate
    model = ScriptedModel.new("clean")
    checker = FakeChecker.new { [] }

    result = run_loop(model: model, checker: checker)

    assert_equal :passed, result.status
    assert_equal "clean", result.source
    assert_equal 1, result.attempts
    assert_empty result.diagnostics
    assert_equal 1, model.prompts.size
  end

  def test_repairs_with_the_latest_diagnostics_then_passes
    model = ScriptedModel.new("bad", "clean")
    checker = FakeChecker.new { |source| source == "bad" ? [error] : [] }

    result = run_loop(model: model, checker: checker)

    assert_equal :passed, result.status
    assert_equal "clean", result.source
    assert_equal 2, result.attempts
    assert_equal 2, model.prompts.size
    assert_includes model.prompts.last, "[I0020]"
    assert_includes model.prompts.last, "repair attempt 2 of 3"
    assert_equal %w[bad clean], checker.seen
  end

  def test_escalates_when_the_budget_is_exhausted
    model = ScriptedModel.new("bad", "bad", "bad")
    checker = FakeChecker.new { [error] }

    result = run_loop(model: model, checker: checker)

    assert_equal :escalated, result.status
    assert_equal 3, result.attempts
    refute_empty result.diagnostics
    assert_equal 3, model.prompts.size
  end

  def test_the_retry_budget_is_configurable
    model = ScriptedModel.new("bad")
    checker = FakeChecker.new { [error] }

    result = run_loop(model: model, checker: checker, retries: 1)

    assert_equal :escalated, result.status
    assert_equal 1, result.attempts
    assert_equal 1, model.prompts.size
  end

  def test_warnings_do_not_block_approval
    model = ScriptedModel.new("warned")
    checker = FakeChecker.new { [warning] }

    result = run_loop(model: model, checker: checker)

    assert_equal :passed, result.status
    assert_equal 1, result.attempts
    refute_empty result.diagnostics
  end

  def test_the_target_is_never_written
    Dir.mktmpdir do |dir|
      target = File.join(dir, "order.xz")
      model = ScriptedModel.new("clean")
      checker = FakeChecker.new { [] }

      RailsXz::Agent::Loop.new(model: model, checker: checker).run(
        intent: "x", target: target
      )

      refute_path_exists target
    end
  end
end
