# Contributing to rails.xz

Thanks for looking. This repository is maintained by two developers with
separate domains, so the workflow is built around small, reviewable changes and
clear ownership. Read [AGENT.md](AGENT.md) first — it defines the working
agreements, and the same rules apply to humans and AI assistants.

## 1. Who owns what

| Area | Owner | Gems / paths |
|---|---|---|
| FFI bridge, binding generation, compiler integration | ax1s-x1zz | `gems/rails-xz-bridge/`, `gems/rails-xz-agent/` (driver) |
| Rails Engine, service DSL, audit dashboard, DX | imrubydev | `gems/rails-xz/`, `examples/` |
| Agent loop, prompt/retry policy | shared | `gems/rails-xz-agent/` |

Cross-domain changes start as an issue, then a PR. Do not push directly to a
gem you do not own without a reviewer from the owning side.

## 2. Local setup

See [docs/07-dev-environment.md](docs/07-dev-environment.md). In short:

```bash
git clone https://github.com/imrubydev/rails-xz.git
cd rails-xz
bundle install
bundle exec rake test
```

You also need the Xz CLI on `PATH` for anything that compiles or checks `.xz`
files. The compiler is not distributed with this repo; build it from the
[Xz repository](https://github.com/x1zzdev/Xz).

## 3. Branching

`main` is always green. Work happens on short-lived branches:

```
feat/<gem>-<topic>     # new capability, e.g. feat/bridge-int-loader
fix/<gem>-<topic>      # bug fix, e.g. fix/engine-badge-color
docs/<topic>           # docs only, e.g. docs/collaboration
chore/<topic>          # tooling, deps, CI
```

Prefix the topic with the gem or area (`bridge`, `agent`, `engine`, `docs`,
`ci`). Keep a branch to one coherent change.

## 4. Commits

- One logical change per commit. A spec gap, a doc fix, and a roadmap update are
  three commits, not one.
- Messages state the decision, not the file list:
  - `bridge: reject non C-representable @export at generation time`
  - `engine: render derived effects, not the declared list`
  - `agent: cap the repair loop at three attempts`
- Author each commit as the developer who did the work.
- Never commit secrets, tokens, or machine-local files.

## 5. Pull requests

1. Push your branch and open a PR against `main`.
2. Fill in the PR template: what changed, which reviewer question it improves,
   and how you verified it (`bundle exec rake test`, `xz check-json`, a manual
   repro).
3. Request a review from the other maintainer. Cross-domain PRs need the owning
   side's approval.
4. CI must pass before merge. At least one approval is required.
5. Merge with a merge commit (keeps the branch context visible) and delete the
   branch.

Small PRs get reviewed faster. If a change touches more than one gem, split it
unless the gems change together for one reason.

## 6. Review etiquette

- Review the contract, not just the code: does the change keep the four reviewer
  questions answerable?
- Prefer a concrete counter-example over a style preference.
- Approve when the change is correct and reviewable; open a follow-up issue for
  improvements that are out of scope.
- If you cannot review within a day, say so and reassign.

## 7. Issues and labels

Use labels to route work: `bridge`, `agent`, `engine`, `docs`, `good first
issue`, `blocked`, `needs-design`. A `needs-design` issue must be resolved in
the specs before implementation.

## 8. Releases

Each gem is versioned independently (semantic versioning) and released from a
tag. A release PR updates the version, the changelog, and any pinned Xz compiler
version together.

## 9. Conduct

Be direct and kind. Critique the work, not the person. Assume good faith.
