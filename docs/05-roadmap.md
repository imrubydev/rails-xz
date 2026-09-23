# 05 — Roadmap

```
Weeks 1–4              Weeks 5–8              Weeks 9–12             Weeks 13–16
  │                      │                      │                      │
  ├─ Phase 1            ├─ Phase 2             ├─ Phase 3             └─ Phase 4
  │  Core FFI & CLI     │  Agent & DSL         │  Audit Engine            Production & release
```

Each phase is owned per the role split in
[06-collaboration.md](06-collaboration.md). `[B]` marks bridge work
(ax1s-x1zz), `[E]` marks Engine work (imrubydev), `[S]` marks shared work.

## Phase 1 — Core FFI binding and CLI validation (Weeks 1–4)

Goal: prove the call path works end to end and is fast enough.

- [ ] `[B]` PoC: call an Xz `@export` function from Ruby through `Fiddle`.
- [ ] `[B]` `.xzint` parser (the subset `xz pkg gen` accepts) and the Ruby
  binding generator fallback.
- [x] `[B]` Type marshalling for scalars, `Str`/`Bytes`, `@cstruct`, and handles.
- [ ] `[B]` `xz check-json` runner and diagnostic parser as a standalone Ruby
  object (used later by the agent).
- [ ] `[S]` Benchmark suite comparing native Ruby logic vs. Xz FFI execution.

Exit criteria: a Rails service object calls an Xz `@export` function through the
generated binding, with measured overhead under 5%.

## Phase 2 — Agent integration and Rails service DSL (Weeks 5–8)

Goal: an LLM writes `.xz` code that passes `xz check-json` without human help,
and a Rails developer can wire it in with a one-line DSL.

- [ ] `[E]` `RailsXz::XzModule` DSL for service objects
  (`xz_module "order", effects: :none`).
- [ ] `[S]` `RailsXz::Agent::GenerateModuleJob` and the N-step repair loop.
- [ ] `[S]` Diagnostic ranking; P1 adds span-based filtering.
- [ ] `[S]` Instrument the KPIs: first-pass rate, self-correction rate,
  escalation rate.
- [ ] `[B]` GVL release policy driven by the derived effect profile.

Exit criteria: ≥ 60% first-pass and ≥ 85% self-correction on the benchmark intent
set, with the loop running entirely inside ActiveJob.

## Phase 3 — Audited Rails Engine (Weeks 9–12)

Goal: a human approves a module in seconds.

- [ ] `[E]` Mountable Engine with `/xz_audit` and the `AuditCard` model.
- [ ] `[E]` ViewComponent cards with effect badges and the `@trusted` marker.
- [ ] `[S]` AST-based effect extraction feeding the card model.
- [ ] `[E]` Unified diff view against the last approved revision.
- [ ] `[B]` P1 one-click approval: `xz build --shared` + binding regeneration +
  a commit authored by the approving developer.

Exit criteria: a reviewer approves a representative module using badges and the
diff alone, with the audit time down ≥ 70% versus line-by-line review.

## Phase 4 — Production hardening and gem release (Weeks 13–16)

Goal: production-ready and installable.

- [ ] `[B]` C ABI runtime memory-leak checks and hot-reload stabilization.
- [ ] `[B]` Version pinning lockfile and `VersionError` hardening.
- [ ] `[E]` Sample Rails app in `examples/demo_app` wiring the full path.
- [ ] `[S]` Publish the `rails-xz`, `rails-xz-bridge`, and `rails-xz-agent`
  gems and tag v0.1.0.

Exit criteria: zero unhandled runtime crashes for approved modules in a
production pilot, and a fresh Rails app runs a first module in under 15 minutes.

## Guiding constraint for every phase

Every feature must make it easier for a human to answer:

*What does it do? What can it change? What are its guarantees? What can go
wrong?*

If a feature makes any of those harder, it is rejected.