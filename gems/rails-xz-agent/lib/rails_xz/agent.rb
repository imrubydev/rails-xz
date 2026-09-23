# frozen_string_literal: true

require "rails_xz/agent/version"
require "rails_xz/agent/errors"
require "rails_xz/agent/diagnostic"
require "rails_xz/agent/check_json"
require "rails_xz/agent/prompt"
require "rails_xz/agent/loop"
require "rails_xz/agent/generate_module_job" if defined?(ActiveJob)

module RailsXz
  # Drives an LLM through the xz check-json diagnostic loop with a bounded retry
  # budget. See docs/02-agent-loop.md.
  module Agent
    class << self
      # The model object used when a job does not pass one explicitly. Any
      # object responding to #generate(prompt) -> String is valid.
      attr_accessor :default_model

      # Optional callback invoked with each Loop::Result, for the audit engine
      # or instrumentation.
      attr_accessor :on_result

      # Convenience entry point.
      #
      #   RailsXz::Agent.run(
      #     intent: "Compute the payable total for an order.",
      #     target: "app/xz/order.xz",
      #     model: client
      #   )
      def run(intent:, target:, model:, shell: nil, retries: Loop::DEFAULT_RETRIES, strict: false)
        Loop.new(model: model, retries: retries, strict: strict)
            .run(intent: intent, target: target, shell: shell)
      end
    end
  end
end