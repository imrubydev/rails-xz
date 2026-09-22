# 04 — Non-functional requirements

## 1. Safety

- The AI Agent may only write `.xz` and `.xzint` files by default. Editing
  `app/controllers`, `app/models`, `config/routes.rb`, `config/`, or
  infrastructure requires an explicit developer flag.
- Approval of a module with unproven, untrusted claims is blocked unless a
  developer overrides with a recorded note (`xz check --strict` parity).
- The agent never commits. Commits are a human action (P1: triggered by audit
  approval, authored by the approving developer).
- The bridge never executes Xz source at runtime; it only loads compiled,
  approved shared objects.

## 2. Determinism and reproducibility

- Given the same Xz version and source, `xz build --shared` produces identical
  binary behavior.
- `rails.xz` pins the Xz compiler version in a lockfile and refuses to bind a
  shared library built by a different version (`VersionError`).
- The agent records the prompt hash and model version for each run so a result
  is reproducible or explainable.

## 3. Developer ergonomics

- Installing `rails.xz` requires zero changes to standard Rails conventions. No
  custom boot, no route rewrites, no config surgery; the audit engine is one
  `mount` line.
- Generated bindings live under a single, predictable directory (default
  `app/xz/bindings/`) and are committed, so a fresh clone runs without a build
  step once `vendor/xz/*.so` is present.
- The default loader uses Ruby's stdlib `Fiddle`, so installation adds no native
  build dependency.
- A developer with no C/Rust knowledge can install the gems and run a first
  AI-generated module in under 15 minutes (PRD KPI).

## 4. No silent degradation

- A value that cannot cross the C ABI safely is a hard error at generation time,
  never a lossy cast.
- A missing symbol or version mismatch is a raised, typed error, not a fallback.
- An unhandled `Result.err` is never converted to a default value.

## 5. Performance

| Path | Budget |
|---|---|
| FFI call overhead | < 5% over a direct C ABI call, excluding the body |
| `xz check-json` on a module | bounded by the compiler; the agent loop adds no full-file reparse beyond one check per attempt |
| Audit page render | interactive (< 100 ms) for a module list |
| Rails boot delta | no measurable change to baseline boot |
| GVL blocking | a slow `io` call must not stall unrelated requests (release the GVL) |

## 6. Observability

- Every FFI call can emit a structured record: function name, declared effects,
  latency, outcome.
- Every agent run emits attempt count, final status, and diagnostic codes.
- Audit actions are logged (who, when, module, decision, override note).

## 7. Compatibility

| Target | Support |
|---|---|
| Ruby | 3.2+ |
| Rails | 7.1+ (Engine, ActiveJob, Hotwire) |
| Job backend | ActiveJob adapter-agnostic (Sidekiq, GoodJob, Solid Queue, `:async`) |
| OS | Linux, macOS, Windows (shared-object suffix per platform) |
| Xz compiler | pinned per release; see the Xz repository |

## 8. Security

- The bridge loads only compiled, approved shared objects; it never runs the
  compiler at request time.
- `.xzint` files fetched from a registry are untrusted until they pass the same
  checks `xz pkg gen` applies (lex, parse, validate, resolve, typecheck).
- No secrets are embedded in generated bindings; configuration is read from the
  environment at load time.
- The audit engine is not mounted in production; if it is mounted deliberately,
  it must be behind the host app's authentication.