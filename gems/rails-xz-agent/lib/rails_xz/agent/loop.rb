# frozen_string_literal: true

require "tempfile"
require "rails_xz/agent/prompt"

module RailsXz
  module Agent
    # Bounded self-correction loop. See docs/02-agent-loop.md.
    #
    #   Loop.new(model: client, retries: 3).run(
    #     intent: "Compute the payable total for an order.",
    #     target: "app/xz/order.xz"
    #   )
    #
    # The model is any object responding to #generate(prompt) -> String. The
    # checker is any object responding to #call(path) -> { diagnostics:,
    # exit_status:, stderr: }. The loop never commits and never writes the
    # target; it checks each candidate in a temporary file and returns the final
    # source on the Result.
    class Loop
      DEFAULT_RETRIES = 3

      Result = Struct.new(:status, :source, :attempts, :diagnostics, keyword_init: true)

      def initialize(model:, checker: nil, retries: DEFAULT_RETRIES, strict: false)
        @model = model
        @checker = checker || CheckJson.new(strict: strict)
        @retries = retries
      end

      def run(intent:, target:, shell: nil)
        prompt = Prompt.new(intent: intent, target: target, shell: shell)
        message = prompt.initial
        attempts = 0

        loop do
          attempts += 1
          source = @model.generate(message)
          diagnostics = check(source)

          return result(:passed, source, attempts, diagnostics) if clean?(diagnostics)
          return result(:escalated, source, attempts, diagnostics) if attempts >= @retries

          message = prompt.repair(
            source: source,
            diagnostics: diagnostics,
            attempt: attempts + 1,
            max_attempts: @retries
          )
        end
      end

      private

      def result(status, source, attempts, diagnostics)
        Result.new(status: status, source: source, attempts: attempts, diagnostics: diagnostics)
      end

      # The candidate is only ever written to a throwaway .xz file: the loop must
      # not touch the target until a human approves it (docs/02-agent-loop.md §6).
      def check(source)
        report = nil
        Tempfile.create(["rails_xz_candidate", ".xz"]) do |file|
          file.write(source)
          file.close
          report = @checker.call(file.path)
        end
        report[:diagnostics]
      end

      def clean?(diagnostics)
        diagnostics.none?(&:error?)
      end
    end
  end
end
