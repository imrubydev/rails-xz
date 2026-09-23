# 02 — Agent self-correction loop

`rails-xz-agent` drives an LLM to write `.xz` code and repairs compiler errors
without human intervention, within a bounded budget. It runs inside an ActiveJob
so the web request thread is never blocked.

## 1. Why the loop works

Xz's compiler is designed for this loop:

- `xz check-json` emits a JSON array of diagnostics.
- Each diagnostic carries a stable `code`, a machine-readable `span`, a
  `category`, and (for intent diagnostics) a `suggestion.fix` with a
  `confidence`.
- Codes are never renumbered or reused, so a fix mapping learned for one error
  stays valid.

Diagnostic schema:

```json
{
  "version": 1,
  "severity": "error",
  "code": "I0020",
  "message": "declared @effects 'none' does not match derived effects 'io' on 'f'",
  "category": "intent",
  "span": { "file": "app/xz/order.xz", "start": [4, 6], "end": [4, 7] },
  "suggestion": { "fix": "extend @effects on 'f' to include 'io'", "confidence": 0.9 }
}
```

## 2. The loop

```
┌──────────────┐
│ intent spec  │  natural language + optional contract shell
└──────┬───────┘
       ▼
┌──────────────┐
│ prompt build │  system rules + spec + (on retry) prior diagnostics
└──────┬───────┘
       ▼
┌──────────────┐
│    LLM       │  writes candidate.xz
└──────┬───────┘
       ▼
┌──────────────┐     errors     ┌──────────────────────────┐
│ xz check-json│ ─────────────► │ rank + filter diagnostics│
└──────┬───────┘                └───────────┬──────────────┘
       │ zero errors                        │
       ▼                                    ▼
┌──────────────┐                    ┌──────────────┐
│  hand off to │                    │ repair prompt│──┐
│  audit engine│                    └──────────────┘  │
└──────────────┘                           ▲          │
                                           └──────────┘
                                        retry while attempts < N
```

The whole loop is one `RailsXz::Agent::GenerateModuleJob`. The job receives an
intent specification and a target path, and enqueues the result (source,
diagnostic history, status) for the audit engine. It never touches a controller
or a request-scoped object.

The loop checks each candidate in a temporary `.xz` file and never writes
`target` itself; the Result carries the final source and the caller decides
where it lands. Writing the module into the app is a human action.

`Loop#run` returns a `Result(status:, source:, attempts:, diagnostics:)` where
`status` is `:passed` (no error diagnostics) or `:escalated` (the budget ran out
with errors still present). The model is any object responding to
`#generate(prompt) -> String`; the checker is any object responding to
`#call(path) -> { diagnostics:, exit_status:, stderr: }`.

## 3. Retry policy

- `N` defaults to **3**. Configurable per call site.
- On each retry, inject only the diagnostics from the latest run — not the full
  history — plus a one-line summary of what changed.
- When `attempts == N` and errors remain, stop and emit `escalated` with the
  final diagnostics and the candidate source. Never commit a failing module.
- The job is idempotent: re-running it with the same inputs and the same model
  version produces the same candidate.

## 4. Diagnostic ranking and filtering

P0: inject all errors, ordered by:

1. `severity` (error before warning),
2. `category` (parse → resolve → type → intent; earlier phases unblock later
   ones),
3. `suggestion.confidence` (highest first).

P1: filter by AST line range. When the agent is editing one function, inject
only diagnostics whose `span` intersects that function's range, plus any
project-wide errors that are prerequisites. This keeps the context small as
files grow.

## 5. Prompt contract

The system prompt states the invariants the agent must preserve:

- Public `func`/`task` (except `main`) require an intent comment (`I0022`).
- Every claim must be paired with a formal `pre`/`post` (`I0021`).
- `@effects` must match the derived profile (`I0020`); allowed labels are
  `none`, `mut`, `io`, `chan`, `extern` (`I0024`).
- An unprovable claim needs `@trusted` with a review note, and only in
  `--strict` (`I0001`, `I0004`).
- `Result` types on the single error channel; no exceptions.
- Only `@export` functions cross the C ABI, and only with C-representable
  signatures.

The agent is told it may only edit `.xz` and `.xzint` files unless a developer
flag widens the scope.

## 6. Safety rails

| Rail | Behavior |
|---|---|
| File scope | Writes limited to `.xz`/`.xzint` by default. Editing `app/controllers`, `app/models`, `config/routes.rb`, or config requires an explicit flag. |
| Retry budget | Hard stop at N; escalation, never silent acceptance. |
| Strict mode | Optional `xz check --strict` so unproven, untrusted claims block. |
| No auto-commit | The agent never commits; approval is a human action in the audit engine. |
| Off the request thread | The loop runs in an ActiveJob, never in a controller. |
| Audit trail | Every attempt (prompt hash, source, diagnostics) is recorded for review. |

## 7. Library surface (planned)

```ruby
result = RailsXz::Agent.run(
  intent: "Compute the payable total for an order.",
  target: "app/xz/order.xz",
  shell: contract_shell,       # optional @intent/@effects scaffold
  retries: 3,
  strict: true,
  model: llm_client            # any object responding to #generate(prompt) -> String
)

# result.status      # => :passed | :escalated
# result.source      # => the final .xz text
# result.attempts    # => Integer
# result.diagnostics # => Array<RailsXz::Agent::Diagnostic>
```

The orchestrator is model-agnostic: it depends only on a
`generate(prompt) -> String` interface, so it wraps any LLM client (OpenAI,
Anthropic, a local model, or a test double).

## 8. Metrics

The loop reports the KPIs from the PRD: first-pass rate, self-correction rate,
and escalation rate. These are recorded per run so a regression in prompt
quality is visible. Counters are exposed through a single `RailsXz::Agent.stats`
object and can be emitted to any instrumentation backend.
