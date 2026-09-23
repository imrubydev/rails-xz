# 03 — Audited Rails Engine

`rails-xz` provides a Rails Engine that renders AI-generated Xz modules as
reviewable cards, so a human can approve or reject in seconds. It is mounted in
one line and is development-only by default.

## 1. Mount

```ruby
# config/routes.rb
mount RailsXz::Engine => "/xz_audit"
```

The Engine is isolated: its own namespace (`RailsXz`), its own tables
(`rails_xz_*`), its own controllers, views, and jobs. It does not reopen Rails
classes and does not touch application routes.

The Engine is mounted only when the host app enables it (default: `development`
and `test`). In production the mount is absent; audit is a development surface.

```
/xz_audit              → list of modules awaiting approval
/xz_audit/modules/:id  → one module: badges, contract, diff, actions
```

## 2. The Audit Card

Each card is backed by a `RailsXz::AuditCard` record and answers the four
reviewer questions directly:

| Reviewer question | Card element | Source |
|---|---|---|
| What does it do? | `@intent` prose + rendered signature | doc comment + Xz AST |
| What can it change? | Effect badges | compiler-derived effects |
| What are its guarantees? | `pre`/`post` list, `@trusted` stamps | doc comment + contract checker |
| What can go wrong? | `Result` error channel + diagnostics history | type signature + `xz check-json` |

The card is rendered with ViewComponent and updated over Hotwire (Turbo
Streams), so approval and new job results appear without a full page reload.

## 3. Effect badges

Badges are derived from the compiler's transitive effect derivation, not from the
declared `@effects` alone. A mismatch is a compile error (`I0020`), so a badge
always describes the real body.

| `@effects` | Badge | Color intent |
|---|---|---|
| `none` | `PURE` | green |
| `mut` | `MUTATES_STATE` | amber |
| `io` | `IO` / `NETWORK_OUT` | blue |
| `chan` | `CONCURRENCY` | purple |
| `extern` | `EXTERNAL_FFI` | red |

A function whose declared effects match the derived profile shows a single badge.
A function carrying an unproven `@trusted` claim shows a distinct "trusted"
marker so the human sees the proof gap, not just the claim.

The Engine renders each badge through `RailsXz::EffectBadgeComponent`, which maps
a label to its badge name and color token and emits
`<span class="xz-effect-badge xz-effect-badge--<color>" data-effect="<label>">`.
The host application owns the palette; the mapping (label, color token) is the
contract. An unknown label raises `EffectBadgeComponent::UnknownEffect` instead
of rendering an uncolored badge.

The card renders declared and derived effects side by side
(`.xz-audit-card__effects`, carrying `data-effects-match`), so the reviewer sees
that the badge describes the body and not just the claim; a divergence is called
out as `I0020`. Every entry of `trusted_claims` renders through
`RailsXz::TrustedMarkerComponent` (`.xz-trusted-marker`) with its claim and
review note, so an unproven claim is visible as a proof gap rather than a fact.

## 4. Diff view

The card shows the candidate source against the last approved revision, stored
as a unified diff in `AuditCard#diff` and parsed by `RailsXz::UnifiedDiff`:

- added/removed lines,
- changed contract lines highlighted (a claim change is as important as a body
  change); a changed line carrying `@intent`, `@requires`, `@ensures`,
  `@effects`, or `@trusted` gets `data-contract-change="true"`,
- the diagnostic run that cleared the candidate (attempt count, final codes).

`RailsXz::DiffComponent` renders both. The clearing run lives in
`AuditCard#diagnostics`:

```json
{ "attempts": 2, "codes": ["I0020"] }
```

`attempts` is how many tries the agent took before the candidate cleared;
`codes` are the diagnostic codes that run reported (empty once the source is
clean). A blank diff renders nothing.

## 5. Approval action

P0: approval is recorded as a state change on the `AuditCard` plus an audit log
entry (who, when, module, decision, override note). The decision request answers
with a Turbo Stream (`text/vnd.turbo-stream.html`) that replaces the card's DOM
id, so the board reflects the new status without a full page reload; a plain
HTML request falls back to the show page.

P1: one-click approval triggers:

1. `xz build --shared --out vendor/xz/<stem>.so <module>.xz`,
2. regeneration of the Ruby binding under `app/xz/bindings/`,
3. a git commit authored by the approving developer, with a message derived from
   `@intent`.

Approval is blocked when `xz check --strict` reports unproven, untrusted claims,
unless a developer explicitly overrides with a recorded note.

## 6. Extraction pipeline

```
.xz source ──► xz check-json (diagnostics + spans)
          ──► effect derivation (transitive)
          ──► AST/doc extraction (@intent, @requires, @ensures, @trusted)
          ──► AuditCard model
```

The AST-based extraction tool is a Phase 3 deliverable. Until the compiler
exposes a full AST dump, extraction uses `xz check --verbose` plus the doc
comments parsed from source. The interface is designed so a richer compiler
output can replace the parser without changing the card model.

## 7. Card model (planned)

```ruby
class RailsXz::AuditCard < ApplicationRecord
  # module_name    :string
  # signature      :text
  # intent         :text
  # declared_effects :json   # ["none"]
  # derived_effects  :json   # ["io"]
  # trusted_claims   :json   # [{ claim:, note: }]
  # diagnostics      :json   # the clearing run: { attempts:, codes: }
  # diff             :text    # unified diff vs last approved
  # status           :string  # pending | approved | rejected | blocked
end
```

JSON columns use the portable `json` type, so the Engine mounts in any host
database (SQLite, PostgreSQL, MySQL); no PostgreSQL-only `jsonb` is required.

## 8. Service DSL

The Engine also owns the service-object DSL that wires an approved module into a
Rails class (Phase 2, [docs/05-roadmap.md](05-roadmap.md)). It is one macro:

```ruby
class Orders::TotalService
  include RailsXz::XzModule
  xz_module "order", effects: :none

  def call(order)
    payable_total(order.subtotal, order.tax_rate)
  end
end
```

- `include RailsXz::XzModule` adds the class macro; `xz_module name, effects:`
  resolves the generated binding `Xz::Bindings::<Camelized name>`
  ([docs/01-bridge.md](01-bridge.md) §6).
- A generated binding declares its functions as module-level methods through
  `RailsXz::Bridge::Facade`, so `include` alone does not make them instance
  methods. The DSL forwards each declared function to the binding; a method the
  service defines itself is never overwritten.
- A missing binding raises `RailsXz::XzModule::MissingBinding`; an effect label
  outside `none`/`mut`/`io`/`chan`/`extern` raises
  `RailsXz::XzModule::UnknownEffect`. Neither degrades silently.
- The declared effect profile and the resolved binding are exposed as class
  metadata (`xz_module_name`, `xz_effects`, `xz_binding`) for the audit board
  and observability. The compiler already guarantees the declared `@effects`
  equals the derived profile (`I0020`), so this metadata mirrors a checked
  claim rather than a hand-maintained one.

## 9. Non-goals

- The audit engine does not edit Xz code. Edits go back through the agent or the
  developer's editor.
- It does not replace `xz check --strict`; it surfaces what the compiler already
  decided.
- It is not a production admin panel. It ships only in development and test.