# rails.xz demo app

A minimal Rails host that wires the full `rails.xz` path in one place: the audit
Engine, the generated binding, and the service DSL. It is the sample app the
[roadmap](../../docs/05-roadmap.md) calls for in Phase 4.

This is a skeleton. It boots and mounts the audit board; the compiled shared
object (`vendor/xz/liborder.so`) is not committed, so calling the module needs a
build first.

## What it shows

| Path | Role |
|---|---|
| `app/xz/order.xz` | the Xz module (`@export payable_total`), reviewed in the audit board |
| `app/xz/order.xzint` | the interface the binding is generated from |
| `lib/xz/bindings/order.rb` | the generated binding (`Xz::Bindings::Order`) |
| `app/services/orders/total_service.rb` | the service DSL (`xz_module "order"`) |
| `config/routes.rb` | the mount, development/test only |

Bindings live under `lib/` so `config.autoload_lib` maps
`lib/xz/bindings/order.rb` to `Xz::Bindings::Order` through Zeitwerk
([docs/03-audit-engine.md](../../docs/03-audit-engine.md) §8).

## Setup

From the repository root, build the Xz CLI and point `XZ_BIN` at it
([docs/07-dev-environment.md](../../docs/07-dev-environment.md)):

```bash
export XZ_BIN="$HOME/Xz/xz-cli/target/release/xz"
cd examples/demo_app
bundle install
bin/rails db:migrate
bin/rails server
```

Then visit `/xz_audit` (development only).

## Build and approve a module

```bash
"$XZ_BIN" build --shared --out vendor/xz/liborder.so app/xz/order.xz
```

The audit board's one-click approval runs the same build, regenerates the
binding from `order.xzint`, and commits all three under
`RailsXz.config.git_identity`.
