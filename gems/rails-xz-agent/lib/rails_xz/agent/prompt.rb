# frozen_string_literal: true

module RailsXz
  module Agent
    # Builds the deterministic prompts the loop hands to the model.
    # See docs/02-agent-loop.md §5.
    class Prompt
      SYSTEM_RULES = <<~TEXT.freeze
        You write Xz modules for a Rails application.

        Preserve these invariants:
        - Public `func`/`task` (except `main`) require an intent comment (`I0022`).
        - Every claim must be paired with a formal `pre`/`post` (`I0021`).
        - `@effects` must match the compiler-derived profile (`I0020`); allowed labels are `none`, `mut`, `io`, `chan`, `extern` (`I0024`).
        - An unprovable claim needs `@trusted` with a review note, and only in `--strict` (`I0001`, `I0004`).
        - `Result` carries the single error channel; do not throw exceptions.
        - Only `@export` functions cross the C ABI, and only with C-representable signatures.

        You may write only `.xz` and `.xzint` files. Return the complete file contents and nothing else.
      TEXT

      def initialize(intent:, target:, shell: nil)
        @intent = intent
        @target = target
        @shell = shell
      end

      def initial
        [SYSTEM_RULES, header, "Write the complete Xz module."].join("\n")
      end

      def repair(source:, diagnostics:, attempt:, max_attempts:)
        [
          SYSTEM_RULES,
          header,
          "This is repair attempt #{attempt} of #{max_attempts}. " \
            "The previous candidate did not compile cleanly.",
          "Fix every diagnostic below while preserving the intent and contract.",
          "Previous candidate:\n#{source}",
          "Diagnostics (latest run, highest priority first):\n" \
            "#{format_diagnostics(diagnostics)}",
          "Return the complete corrected Xz module and nothing else."
        ].join("\n\n")
      end

      private

      def header
        <<~TEXT.chomp
          Target file: #{@target}

          Intent:
          #{@intent}

          Contract shell:
          #{@shell || "(none)"}
        TEXT
      end

      # Ranked with Diagnostic#rank and rendered one per line. Only the latest
      # run's diagnostics are shown; the history is not replayed.
      def format_diagnostics(diagnostics)
        diagnostics.sort_by(&:rank).map { |diagnostic| format_diagnostic(diagnostic) }.join("\n")
      end

      def format_diagnostic(diagnostic)
        line = +"- [#{diagnostic.code}]"
        line << " #{diagnostic.category}" if diagnostic.category
        line << " at line #{diagnostic.line}" if diagnostic.line
        line << ": #{diagnostic.message}"
        fix = diagnostic.suggestion && diagnostic.suggestion["fix"]
        line << "\n  fix: #{fix}" if fix
        line
      end
    end
  end
end
