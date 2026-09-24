# Product Requirements Document (PRD): `rails.xz`

**Version:** 0.1.0-draft
**Status:** Proposal
**Authors:** imrubydev (Rails Engine & DX) · ax1s-x1zz (FFI bridge & compiler integration)
**Target architecture:** Ruby on Rails (Ruby 3.x) + Xz native compiler/JIT
(`xz check-json`, `xz build --shared`) through a Ruby Native FFI bridge

---

## 1. Executive summary

### 1.1 Vision and thesis

`rails.xz` is a hybrid Rails toolkit that combines Rails' unmatched web
development productivity with Xz's strict compile-time verification. It is built
around a single thesis:

> **Rails drives the structure and orchestration; Xz provides the high-performance,
> high-safety logic sandbox that AI writes into.**

Rails keeps 100% of its strengths — ActiveRecord, routing, Hotwire/ERB, and
developer experience. The logic that needs static verification and low-level
performance is quarantined into `.xz` modules written by an AI Agent. Xz's
explicit contracts (`@intent`, `@requires`, `@ensures`, `@effects`, `@trusted`)
and its automated feedback engine (`xz check-json`) let the toolkit absorb a
safe, low-level backend engine into a Rails app without the overhead of writing a
C extension.

### 1.2 Scope

In scope: the Ruby FFI bridge, the agent self-correction pipeline, and the Rails
Engine audit dashboard.

Out of scope: the Xz language, compiler, and runtime themselves. Those live in
the [Xz repository](https://github.com/x1zzdev/Xz). `rails.xz` consumes their
stable surfaces — the CLI, JSON diagnostics, the shared-library C ABI, and
`.xzint` interface files.

---

## 2. Problem statement and opportunities

| Existing Rails limitation | Opportunity `rails.xz` provides |
|---|---|
| **No static verification or type safety.** Ruby's dynamic nature makes runtime errors and side-effect drift hard to trace in large business logic or complex calculations. | **Compile-time contract enforcement.** Xz's `@intent` and `@effects` contracts block side effects, infinite loops, and overflow from AI-written logic at compile time. |
| **Adopting another language is expensive.** Linking C extensions or Rust (`rb-sys`) forces developers to hand-write dual bindings and memory management. | **AI-synthesized C ABI.** No human-written C/Rust: the Agent writes an Xz module and `xz build --shared` emits a C ABI library that the bridge binds through Native FFI. |
| **Uncertainty in AI-generated code.** LLM-written Ruby can pollute Rails' implicit context (monkey patching, global state). | **An isolated pure-logic sandbox.** The Agent's scope is fully contained in `*.xz` files; the Rails orchestration layer is never contaminated. |
| **Slow, risky review of generated code.** | **One-glance audit.** The `/xz_audit` dashboard renders contract and effect badges plus a diff, so a human approves in seconds. |

---

## 3. System architecture and component interactions

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Ruby on Rails web layer                         │
│  Controllers · ActionCable · Views (Hotwire / ERB)                      │
│  ActiveRecord (ORM, migrations, validations) · routing · auth          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Ruby Native FFI (Fiddle / ffi)
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      rails.xz orchestration engine                     │
│                                                                        │
│  ┌───────────────────────────┐      ┌───────────────────────────────┐  │
│  │ Ruby Agent controller     │ ───► │ `xz check-json` feedback loop │  │
│  │ (ActiveJob / Sidekiq)     │      │ (LLM self-correction loop)    │  │
│  └─────────────┬─────────────┘      └───────────────┬───────────────┘  │
│                │                                    │                  │
│                ▼                                    ▼                  │
│  ┌───────────────────────────┐      ┌───────────────────────────────┐  │
│  │ Rails Engine audit board  │ ◄─── │ Native C ABI shared library   │  │
│  │ (Hotwire / ViewComponent) │      │ (`.so` / `.dylib` / `.dll`)   │  │
│  └───────────────────────────┘      └───────────────────────────────┘  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ C ABI / shared-library calls
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         Xz core engine (.xz)                           │
│  LLVM JIT / native binary compilation                                  │
│  Explicit contracts: @intent · @requires · @ensures · @effects         │
│  Value semantics and memory safety                                     │
└────────────────────────────────────────────────────────────────────────┘
```

Component contracts are specified in [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 4. Personas and core workflow

### 4.1 Personas

1. **The Rails Architect (Human).** Owns the ActiveRecord model, controllers,
   web UI, and the overall workflow. Writes the intent of each backend unit and
   performs the final audit/approval of AI-generated Xz modules.
2. **The AI Backend Agent (Writer).** Receives a prompt and an input/output
   spec, writes the `.xz` business logic, reads `xz check-json` diagnostics, and
   repairs compiler errors independently within a bounded budget.

### 4.2 Core workflow

1. **Requirement / contract shell.** A human defines the Xz module spec
   (`@intent`, `@effects`) inside a Rails action or service object.
2. **AI code generation.** The Agent writes the `.xz` module.
3. **Automated verification.** `rails.xz` runs `xz check-json` in a background
   job (ActiveJob / Sidekiq). On error, the JSON diagnostics are parsed and fed
   back to the Agent for self-correction (up to N retries).
4. **Human audit.** On zero errors, the built-in audit dashboard (Hotwire)
   renders a visual report: the `@intent` spec, the `@effects` matrix, and the
   code diff. The human clicks **Approve**.
5. **Dynamic FFI compilation and binding.** On approval, `xz build --shared`
   compiles the shared library, and the Ruby FFI/Fiddle wrapper maps the C ABI
   functions so the Rails service object can call them immediately.

---

## 5. Detailed feature requirements

### 5.1 Xz–Ruby FFI bridge engine (`rails-xz-bridge`)

- **P0 — Dynamic library loader.** Load compiled `.so` / `.dylib` / `.dll` files
  from `vendor/xz` with hot-reloading, without restarting the Rails process.
- **P0 — Type marshalling.** A fast C-marshal layer converting between Ruby
  primitives (`Integer`, `Float`, `String`, `Hash`) and Xz's statically typed
  structures.
- **P0 — Binding generator.** Emit Ruby bindings from `.xzint` interfaces or the
  header produced by `xz build --shared`, mirroring the existing
  `xz pkg gen --lang python` flow with a Ruby target.
- **P0 — Only `@export` functions cross the boundary.** Every exported signature
  must be C-representable end to end (`Bool`, `Int`, `usize`, `Float`, `Char`,
  `Str`, `Bytes`, `Ptr`, `@cstruct record`; `Unit` return only). A non
  C-representable signature is a hard error, never a lossy cast.
- **P1 — `Result` marshalling.** A C ABI export cannot carry a `Result`; the
  sanctioned pattern is a thin contracted Xz wrapper that maps the error channel
  to an out-parameter or status code, which the Ruby binding re-raises as a
  typed error.
- **P1 — Ownership transfer.** A `.xzint foreign` function may mark a pointer
  parameter or return `transfer`; the binding takes or hands back ownership,
  allocating a callee-owned buffer for a transfer parameter and calling the
  named `release` symbol for a transfer return instead of leaking it.

### 5.2 Agent self-correction pipeline (`rails-xz-agent`)

- **P0 — JSON diagnostics parser.** Parse `xz check-json` output into a Ruby
  Hash, converting error line numbers and reasons into a prompt structure.
- **P0 — ActiveJob integration.** Keep AI generation and compile verification
  off the web request thread by running them as asynchronous background jobs.
- **P0 — Strict N-step retry threshold** (default `N = 3`). Escalate to human
  review when unresolved; never accept a failing module silently.
- **P1 — Diagnostic ranking and span filtering** to keep the prompt context
  small as modules grow.

### 5.3 Audit dashboard (Rails Engine UI)

- **P0 — Embedded Rails Engine.** Mount with one line:
  `mount RailsXz::Engine => "/xz_audit"`.
- **P0 — Side-effect matrix visualizer.** Render `@effects` (e.g. `io`,
  `mut`, `extern`, `chan`) as risk-colored badges derived from the compiler's
  transitive effect profile, not the declared list alone.
- **P0 — Visual diff and approve trigger.** On approval, create a git commit and
  automate the C ABI library build.
- **P1 — Strict-mode gate.** Block approval of modules with unproven, untrusted
  claims unless a developer overrides with a recorded note.

---

## 6. Key performance indicators

| Metric | Target | Description |
|---|---|---|
| AI self-correction rate | ≥ 85% | Compiler errors resolved by the Agent via `xz check-json` within 3 retries, with no human intervention. |
| Audit time per module | −70% vs. baseline | Time to review and approve an AI-generated module using effect badges and contract visualization, compared to line-by-line review of C/Rust/Ruby. |
| FFI execution overhead | < 5% | Runtime overhead through the Ruby FFI wrapper versus a direct C ABI call. |
| Rails developer onboarding | < 15 min | Time for an existing Rails developer to install `rails.xz` and run a first AI-generated Xz module, with no C/Rust knowledge. |
| First-pass compilation rate | ≥ 60% | Initial AI-generated `.xz` files that pass `xz check-json` on the first attempt. |

Targets are measured per release on the benchmark suite introduced in
[docs/05-roadmap.md](docs/05-roadmap.md) Phase 1.

---

## 7. Phase-by-phase roadmap

```
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 1: Core FFI binding & CLI validation (Weeks 1–4)                 │
│ - Ruby Fiddle/FFI proof of concept calling an Xz C ABI function        │
│ - Gem that runs `xz check-json` from Ruby and parses diagnostics       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 2: Agent integration & Rails service DSL (Weeks 5–8)             │
│ - `Xz::Module` DSL for Rails service objects                           │
│ - ActiveJob-based generation + `xz check-json` self-correction loop    │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 3: Rails Engine audit dashboard (Weeks 9–12)                     │
│ - Hotwire / ViewComponent audit dashboard                              │
│ - @intent / @effects badges and one-click C ABI build + approve        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Phase 4: Production hardening & gem release (Weeks 13–16)              │
│ - C ABI runtime memory-leak checks and hot-reload stabilization        │
│ - Publish the `rails-xz` gems and a sample Rails project               │
└────────────────────────────────────────────────────────────────────────┘
```

Full breakdown: [docs/05-roadmap.md](docs/05-roadmap.md).

---

## 8. Non-functional requirements

1. **Safety first.** The Agent may only write `.xz` / `.xzint` files. Editing
   Rails controllers, models, routes, or infrastructure requires an explicit
   developer flag.
2. **Deterministic reproducibility.** Given the same prompt and Xz version,
   compilation output must produce identical binary behavior.
3. **Developer ergonomics.** Installing `rails.xz` requires zero changes to
   standard Rails conventions: no custom boot, no route rewrites, one line to
   mount the Engine.
4. **No silent degradation.** A value that cannot cross the C ABI safely is a
   hard error, never a lossy cast.
5. **Version pinning.** The bridge records the Xz compiler version it was built
   against and refuses to bind an incompatible shared library.
6. **Observability.** Every FFI call can emit a structured record (function,
   declared effects, latency, outcome) for production auditing.

Details: [docs/04-nfr.md](docs/04-nfr.md).
