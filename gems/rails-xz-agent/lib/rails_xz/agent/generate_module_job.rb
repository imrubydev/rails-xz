# frozen_string_literal: true

module RailsXz
  module Agent
    # Runs the self-correction loop off the web request thread.
    #
    # The job is idempotent for the same inputs and model version. It never
    # commits and never edits Rails files (docs/02-agent-loop.md §6).
    class GenerateModuleJob < ActiveJob::Base
      queue_as :default

      def perform(intent:, target:, retries: Loop::DEFAULT_RETRIES, model: nil)
        result = Loop.new(
          model: model || RailsXz::Agent.default_model,
          retries: retries
        ).run(intent: intent, target: target)

        RailsXz::Agent.on_result&.call(result)
        result
      end
    end
  end
end