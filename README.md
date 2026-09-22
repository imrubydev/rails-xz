# rails.xz

A hybrid Rails toolkit that bridges **Ruby on Rails** with the **Xz programming
language**.

> **AI-written, Human-reviewed.**

Rails owns the web layer: ActiveRecord, routing, controllers, Hotwire views, and
developer experience. Xz owns the backend logic that must be fast, isolated, and
verifiable. Because Xz makes every behavior explicit — typed contracts, value
semantics, derived effect profiles, structured JSON diagnostics — an AI Agent can
write backend code safely, self-correct against `xz check-json`, and hand a human
a one-glance audit instead of a multi-file Ruby diff.

## Why

| Problem | How rails.xz answers it |
|---|---|
| Dynamic Ruby hides side effects and runtime bugs in large AI-written logic. | Xz requires `@intent` / `@effects` at every public boundary and derives the real effect profile from the body. A mismatch is a compile error (`I0020`). |
| Reaching for C/Rust means hand-written bindings and memory management. | The Agent writes an `.xz` module; `xz build --shared` emits a C ABI library that the bridge loads through Ruby's FFI. No C extension to maintain. |
| Reviewing AI-generated Ruby is slow and unsafe. | A human audits contract and effect badges plus a diff on `/xz_audit`, not deep code paths. |
| LLM output can pollute Rails' implicit context (monkey patches, globals). | Generated logic is fully quarantined in `*.xz` files; Rails orchestration is never touched by the Agent. |

## Architecture

```
Rails web layer (Controllers · ActiveRecord · Hotwire/ERB · ActionCable)
        │  Ruby Native FFI (Fiddle / ffi) over a generated binding
        ▼
rails.xz  ── bridge · agent · audit engine
        │  C ABI shared library (.so / .dylib / .dll)
        ▼
Xz core (.xz)  ── LLVM native / shared library / JIT
                 contracts: @intent · @requires · @ensures · @effects
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the component contracts and
[prd.md](prd.md) for the product requirements.

## Gems (planned)

| Gem | Role | Owner |
|---|---|---|
| `rails-xz-bridge` | Generate Ruby bindings from `.xzint` interfaces; load and call Xz shared libraries through `Fiddle`/`ffi`. | ax1s-x1zz |
| `rails-xz-agent` | Drive the LLM → `xz check-json` → repair loop on ActiveJob with a bounded retry budget. | shared |
| `rails-xz` | Rails Engine: `Xz::Module` service DSL and the `/xz_audit` dashboard for human approval. | imrubydev |

## Quick start (target)

```ruby
# 1. Write a contract shell (human or agent)
#    app/xz/order.xz
#   /// Computes the payable total for an order.
#   /// @intent  Sums line items and applies the tax rate.
#   /// @ensures result >= 0.0
#   /// @effects none
#   @export func payable_total(subtotal: Float, tax_rate: Float) -> Float
#       post result >= 0.0
#   {
#       subtotal * (1.0 + tax_rate)
#   }
```

```bash
# 2. Deterministic verification
xz check-json app/xz/order.xz

# 3. Compile and bind
xz build --shared --out vendor/xz/liborder.so app/xz/order.xz
```

```ruby
# 4. Use it from a Rails service object
class Orders::TotalService < ApplicationService
  include RailsXz::XzModule

  xz_module "order", effects: :none

  def call(order)
    payable_total(order.subtotal, order.tax_rate)
  end
end
```

## Status

**v0.1.0-draft — design and scaffolding.** This repository holds the PRD, the
architecture, the subsystem specs, and the gem skeletons. The Xz compiler it
targets lives in the [Xz repository](https://github.com/x1zzdev/Xz);
`xz check-json`, `xz build --shared`, `xz bind`, and the LSP server are already
implemented there. The Ruby bridge, the agent loop, and the Rails Engine are the
work this repo tracks.

## Repository layout

```
rails-xz/
├── README.md
├── prd.md                     # Product requirements (authoritative scope)
├── ARCHITECTURE.md            # Components, contracts, data flow
├── AGENT.md                   # Working agreements for contributors/AI
├── CONTRIBUTING.md            # Roles, branching, commit and review flow
├── docs/
│   ├── 01-bridge.md           # Ruby FFI + binding generation
│   ├── 02-agent-loop.md       # Self-correction pipeline
│   ├── 03-audit-engine.md     # Rails Engine audit dashboard
│   ├── 04-nfr.md              # Non-functional requirements
│   ├── 05-roadmap.md          # Phase plan
│   ├── 06-collaboration.md    # Two-developer workflow
│   └── 07-dev-environment.md  # Local setup and the Xz toolchain
├── gems/
│   ├── rails-xz/              # Engine + service DSL + audit UI
│   ├── rails-xz-bridge/       # FFI bridge + binding generator
│   └── rails-xz-agent/        # Agent self-correction loop
└── examples/                  # Contract examples and a demo app (later)
```

## Maintainers

- **imrubydev** — Rails Engine, service DSL, and developer experience. Started
  the project; owns the repo.
- **ax1s-x1zz** — FFI bridge, binding generation, and compiler integration.

See [docs/06-collaboration.md](docs/06-collaboration.md) for how the two work
together.

## License

MIT — see [LICENSE](LICENSE).
