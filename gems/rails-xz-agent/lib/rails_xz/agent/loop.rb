# frozen_string_literal: true

module RailsXz
  module Agent
    # Bounded self-correction loop. See docs/02-agent-loop.md.
    #
    #   Loop.new(model: client, checker: CheckJson.new, retries: 3).run(
    #     intent: "Compute the payable total for an order.",
    #     target: "app/xz/order.xz"
    #   )
    #
    # The concrete prompt building and repair loop land in Phase 2.
    class Loop
      DEFAULT_RETRIES = 3

      Result = Struct.new(:status, :source, :attempts, :diagnostics, keyword_init: true)

      def initialize(model:, checker: CheckJson.new, retries: DEFAULT_RETRIES, strict: false)
        @model = model
        @checker = checker
        @retries = retries
        @strict = strict
      end

      def run(intent:, target:, shell: nil)
        raise NotImplementedError,
              "the repair loop lands in Phase 2 (docs/05-roadmap.md)"
      end
    end
  end
end