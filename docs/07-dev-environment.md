# 07 — Development environment

How to set up a machine to work on `rails.xz`. Keep this page current; if a step
becomes stale, fix it in the same PR as the change that made it stale.

## 1. Prerequisites

| Tool | Version | Why |
|---|---|---|
| Ruby | 3.2+ | Engine, gems, Fiddle |
| Bundler | current | Gem dependencies |
| Rails | 7.1+ | Engine host for the demo app |
| Xz CLI | current | `xz check-json`, `xz build --shared`, `xz bind` |
| Node.js | 22+ | Only for the opencode plugin under `.opencode/` |

The Xz compiler is not distributed with this repository. Build it from the
[Xz repository](https://github.com/x1zzdev/Xz):

```bash
git clone https://github.com/x1zzdev/Xz.git
cd Xz/xz-cli
cargo build --release
```

## 2. The `xz` PATH trap

On Linux, `/usr/bin/xz` is **XZ Utils** (the compression tool), not the Xz
language CLI. Running `xz check-json` will silently invoke the wrong program.
Never rely on bare `xz` being the language CLI.

Point the tooling at the language CLI explicitly through `XZ_BIN`:

```bash
export XZ_BIN="$HOME/Xz/xz-cli/target/release/xz"
"$XZ_BIN" check-json app/xz/order.xz
```

Every script and test in this repo must read `XZ_BIN` (falling back to a clear
error if it is unset) rather than assuming `xz` on `PATH`. A future `xz-lang`
wrapper on `PATH` is preferred, but until then `XZ_BIN` is the contract.

## 3. Clone and install

```bash
git clone https://github.com/imrubydev/rails-xz.git
cd rails-xz
bundle install
```

## 4. Repository layout

```
rails-xz/
├── gems/
│   ├── rails-xz/          # Engine + service DSL + audit UI
│   ├── rails-xz-bridge/   # FFI bridge + binding generator
│   └── rails-xz-agent/    # Agent self-correction loop
├── examples/              # Contract examples; demo app (later)
├── vendor/xz/             # compiled .so drop (gitignored)
├── docs/                  # subsystem specs
├── prd.md, ARCHITECTURE.md, AGENT.md, CONTRIBUTING.md
└── .opencode/             # /next_ax1s and /next_ruby commands
```

Each gem is a normal, independently testable gem with its own `Gemfile`,
`*.gemspec`, and `test/`.

## 5. Verify

Run the checks for whatever you touched. Do not guess commands; these are the
repository's definitions.

```bash
# All gems (from the repo root)
bundle exec rake test

# A single gem
cd gems/rails-xz-bridge && bundle install && bundle exec rake test

# Any .xz file you added or changed
"$XZ_BIN" check-json "$file"

# Lint (once configured)
bundle exec rubocop
```

There is no CI yet; Phase 1 adds a GitHub Actions workflow that runs the same
commands.

## 6. Environment variables

| Variable | Purpose | Default |
|---|---|---|
| `XZ_BIN` | Path to the Xz language CLI | unset — required for Xz operations |
| `XZ_LIB_DIR` | Directory of compiled `lib*.so` libraries | `vendor/xz` |
| `RAILS_XZ_ENV` | Enable the audit Engine outside development | `development` |
| `RAILS_XZ_STRICT` | Run `xz check --strict` in the agent loop | `false` |

## 7. Trying the audit engine

From the (future) demo app:

```ruby
# config/routes.rb
mount RailsXz::Engine => "/xz_audit"
```

Then visit `/xz_audit`. In a real host app the Engine is mounted only in
`development`/`test`.

## 8. The opencode workflow

Local AI sessions use two commands, each bound to one developer's queue:

- `/next_ax1s` → reads `NEXT_ax1s.md`, works bridge/compiler items.
- `/next_ruby` → reads `NEXT_ruby.md`, works Engine/DX items.

Both queues are gitignored. The exact commit-identity command for each developer
lives in `.local/OPERATIONS.md` (also gitignored). See that file before doing any
git operation.

## 9. Known gaps

- Ruby/Rails are not installed on every development machine yet; the gem
  skeletons exist but have not been executed. Phase 1's first task is to run
  `bundle exec rake test` on a real Ruby.
- The demo app in `examples/demo_app` does not exist yet (Phase 4).