# Examples

Design-validation `.xz` modules and the target Rails usage. These must comply
with the Xz specification in the
[Xz repository](https://github.com/x1zzdev/Xz); they never invent syntax.

| Example | What it validates |
|---|---|
| `order.xz` | A pure `@export` function bound through the bridge and called from a service object. |
| `parse_amount.xz` | The contracted-wrapper pattern for a `Result` (status + out-parameter). |

The demo Rails app (`examples/demo_app`) lands in Phase 4
([docs/05-roadmap.md](../docs/05-roadmap.md)).