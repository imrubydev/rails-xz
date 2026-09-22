# Architecture

This document specifies how `rails.xz` is put together: the components, the
interfaces between them, and the data that flows across each boundary. It
assumes the Xz language surfaces described in the
[Xz specification](https://github.com/x1zzdev/Xz).

## 1. Why a toolkit, not a fork of Rails

`rails.xz` is a **set of gems plus a mountable Engine**, not a fork of Rails.
This is a deliberate decision, recorded here so it is not reopened by accident.

- **A fork does not survive.** Rails moves fast; a fork must rebase every change
  and would carry the whole framework to ship a small FFI feature. A gem/Engine
  rides the upstream release train instead.
- **The PRD's own interface is a mount point.** The required integration is
  `mount RailsXz::Engine => "/xz_audit"` plus a service-object mixin. Both are
  standard Rails extension points; neither needs framework changes.
- **A Rails Engine is already isolated.** It has its own namespace, tables,
  routes, controllers, and views. That is exactly the "quarantine" the project
  wants, without touching Rails internals.
- **The equivalent sibling project made the same call.** `next.xz` is a package
  monorepo layered on top of Next.js, not a patched Next.js. Consistency keeps
  the two projects' mental models aligned.

What we do NOT do: patch `ActionController`, reopen `ActiveRecord::Base`, or
monkey-patch Rails. If a requirement seems to need that, it is a design error
and goes back to the PRD.

## 2. Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer A — Rails application (developer-owned)                       │
│   Controllers · ActiveRecord · Hotwire/ERB · ActionCable · jobs     │
└───────────────┬─────────────────────────────────────────────────────┘
                │  include RailsXz::XzModule
                │  xz_module "order", effects: :none
┌───────────────▼─────────────────────────────────────────────────────┐
│ Layer B — rails-xz-bridge (generated binding + runtime)             │
│   binding generator · FFI loader · marshalling · error mapping      │
└───────────────┬─────────────────────────────────────────────────────┘
                │  C ABI symbols (Fiddle / ffi)
┌───────────────▼─────────────────────────────────────────────────────┐
│ Layer C — Xz shared library (compiled artifact)                     │
│   @export functions · @cstruct layouts · libc runtime               │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ Layer D — rails-xz-agent (dev-time, ActiveJob / Sidekiq worker)     │
│   prompt builder · xz check-json driver · repair loop · retry budget│
└───────────────┬─────────────────────────────────────────────────────┘
                │  reads diagnostics, writes .xz
┌───────────────▼─────────────────────────────────────────────────────┐
│ Layer E — rails-xz Engine (dev-time Rails mount /xz_audit)          │
│   AST effect extraction · badge rendering · approval action         │
└─────────────────────────────────────────────────────────────────────┘
```

Layers B and C are the production path. Layers D and E are development-time
tooling that never ship to production; the Engine is mounted only in the
development (and optionally staging) environment.

## 3. Component contracts

### 3.1 `rails-xz-bridge`

Inputs: an `.xzint` interface file or a `.xz` source with `@export` functions.
Outputs: a Ruby module with typed methods and a loader.

```ruby
# generated: app/xz/bindings/order.rb
module Xz::Bindings::Order
  extend RailsXz::Bridge::Facade
  payable_total(subtotal: :double, tax_rate: :double) # -> Float
end

# generated: app/xz/bindings/_loader.rb
# Loads vendor/xz/liborder.so through Fiddle (default) or ffi.
# Raises RailsXz::Bridge::VersionError if the library's xz version != pinned.
```

Rules:

- Only `@export` symbols are bound. Non-exported functions keep internal
  linkage and are unreachable.
- The generator mirrors `xz bind --lang python`: it reads the same `@export`
  signatures and `@cstruct` records, and emits a wrapper named after the source
  stem.
- A signature that is not C-representable is a generator error, not a warning.
  This matches the compiler's own rule for `@export`.
- `Result` cannot cross the C ABI. A C-representable Xz wrapper is required; the
  Ruby binding maps its status/out-parameter back to a raised typed error. See
  [docs/01-bridge.md](docs/01-bridge.md).

### 3.2 `rails-xz-agent`

Inputs: an intent specification (natural language + optional contract shell).
Outputs: an `.xz` file, a diagnostic history, and a terminal status
(`passed` | `escalated`).

```
intent ──► prompt ──► LLM ──► candidate.xz
                                  │
                                  ▼
                          xz check-json
                          │           │
                     errors?       zero errors
                          │           │
                          ▼           ▼
                    repair prompt   hand to audit
                          │
                          └──► retry (≤ N)
```

Rules:

- The loop is bounded by N (default 3). On exhaustion it stops and escalates; it
  never silently accepts a failing module.
- Generation and verification run inside an ActiveJob, never on the request
  thread. The job holds no Rails request state.
- Only diagnostics whose `span` intersects the current edit target are injected
  (P1), ranked by `suggestion.confidence`.
- The agent may write `.xz` files and `.xzint` interface files. It may not edit
  `app/controllers`, `app/models`, `config/routes.rb`, or infrastructure without
  an explicit developer flag.
- Every iteration is recorded so the audit view can show the path taken.

### 3.3 `rails-xz` Engine

Inputs: the approved-candidate `.xz` file and the diagnostic run that cleared
it. Outputs: an approval event that triggers `xz build --shared` and a commit.

Data rendered per module:

| Field | Source |
|---|---|
| Signature | Xz AST / `xz check --verbose` |
| `@intent` prose | doc comment |
| Declared `@effects` | doc comment |
| Derived `@effects` | compiler effect derivation |
| `@trusted` stamps | doc comment, with review note |
| Diff | git against the last approved revision |

The Engine is a standard Rails Engine: an isolated namespace (`RailsXz`),
isolated tables (`rails_xz_*`), its own routes, and a single mount point.

## 4. Type mapping across the bridge

Xz ↔ C (authoritative, from the Xz spec), with the Ruby representation the
bridge produces:

| Xz | C | Ruby binding |
|---|---|---|
| `Bool` | `bool` (i8 in memory, i1 in registers) | `true` / `false` |
| `Int` | `int64_t` | `Integer` |
| `usize` | `uint64_t` | `Integer` |
| `Float` | `double` | `Float` |
| `Char` | `char` | `String` (length 1) |
| `Str` | `XzStr { const char* ptr; size_t len; }` | `String` (encoded/decoded) |
| `Bytes` | `XzBytes { uint8_t* ptr; size_t len; }` | `String` (ASCII-8BIT) |
| `Ptr` | `void*` | opaque handle object (never copied) |
| `@cstruct record` | C `struct`, declaration order | `Data` / `Struct` subclass |
| `Result` / `Option` | not C-representable | mapped by a contracted wrapper (§3.1) |
| `List` / `Map` / `Set` / `enum` / plain `record` / `Chan` | not C-representable | rejected at generation time |

`Str`/`Bytes` cross as two-field structs (pointer + length, no NUL guarantee).
`mut` parameters map to `T*` (C in/out); the Ruby binding allocates the cell,
passes its address, and reads the updated value back.

### 4.1 The GVL and thread safety

An Xz shared library is native code that may block (I/O, long computation). The
loader releases Ruby's GVL around a call when the bound function is declared
`@effects io` or otherwise non-trivial, so a slow Xz function does not stall the
whole Rails process. Functions declared `@effects none` run under the GVL
because they are pure and short. The effect profile from the compiler is the
source of truth for this decision — it is not guessed from the name.

## 5. Effect badges

Xz derives a function's effect profile transitively over calls. The audit UI maps
the derived labels to reviewer-facing badges:

| `@effects` label | Badge | Reviewer question answered |
|---|---|---|
| `none` | `PURE` | "What can it change?" → nothing |
| `mut` | `MUTATES_STATE` | "What can it change?" → explicit local mutation |
| `io` | `IO` / `NETWORK_OUT` | "What can it change?" → filesystem/clock/network |
| `chan` | `CONCURRENCY` | "What can it change?" → inter-task messages |
| `extern` | `EXTERNAL_FFI` | "What can it change?" → foreign code |

A declared/derived mismatch is a compile error (`I0020`); the badge therefore
always reflects the body, not just the claim.

## 6. Failure model

- **Compile-time:** `xz check-json` returns a JSON array of diagnostics with
  stable codes (`L`/`P`/`R`/`T`/`I` prefixes), spans, categories, and suggested
  fixes. This is the only feedback channel the agent uses.
- **Generation-time:** a non-C-representable `@export` or a missing `.xzint`
  symbol is a hard error; the bridge refuses to emit a lossy binding.
- **Load-time:** a missing symbol or an Xz version mismatch raises
  `RailsXz::Bridge::SymbolError` / `VersionError`, never a silent fallback.
- **Runtime:** approved modules return `Result`; the wrapper maps the error
  channel to a typed Ruby exception at the service-object boundary. An unhandled
  `err` reaching `main` is printed to stderr and exits non-zero — the one error
  path the runtime owns.

## 7. Hot-reloading

`rails-xz-bridge` can reload a shared library without restarting Rails:

1. the loader holds a handle per library path and a monotonic build stamp,
2. `reload!` (or a dev-only file watcher) `dlclose`s the previous handle and
   `dlopen`s the new one,
3. generated bindings re-resolve their symbols against the new handle.

Because Rails may already hold references to the old binding, hot-reload is a
development convenience only and is disabled in production. Reloading a library
while a call is in flight is undefined; the loader never reloads mid-call.

## 8. Determinism

Given the same Xz version and source, `xz build --shared` produces identical
binary behavior. `rails.xz` pins the compiler version in a lockfile and refuses
to bind a shared library built by a different version.

## 9. Trust boundaries

| Boundary | Trusted side | Rule |
|---|---|---|
| LLM → `.xz` source | neither | compiler verifies before use |
| `.xz` → shared library | compiler | only `@export`, C-representable |
| `.so` → Ruby binding | generator | version-pinned, no lossy casts |
| Agent → Rails files | developer | agent blocked without a flag |
| Audit → build/commit | developer | approval is a human action |