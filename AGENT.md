# AGENT.md — Working agreements for this repository

`rails.xz` is in the **design and scaffolding phase**: the product of this repo
is the PRD, the architecture, the subsystem specs, and the gem skeletons.
Everything an AI assistant does here must make the AI-written backend *more
reviewable* — that is the whole point of the project.

## Repo layout

- `prd.md` — authoritative scope. If a requirement is not here, it is not
  committed work.
- `ARCHITECTURE.md` — component contracts, type mapping, trust boundaries.
- `docs/01..07` — per-subsystem specs (bridge, agent loop, audit Engine, NFRs,
  roadmap, collaboration, dev environment). Each spec owns its subsystem's
  details; the PRD owns priorities.
- `gems/` — the three gems: `rails-xz` (Engine), `rails-xz-bridge` (FFI),
  `rails-xz-agent` (loop). Each gem is independently versioned and testable.
- The Xz language itself lives in the
  [Xz repository](https://github.com/x1zzdev/Xz). Do not duplicate its
  specification here; link to it.

## Ground rules

1. **Reviewability gate.** Every change must strengthen the answer to the four
   reviewer questions: *What does it do? What can it change? What are its
   guarantees? What can go wrong?* If a proposed feature makes any of them
   harder, reject it.
2. **Docs are the contract.** A new capability goes into the PRD (priority) and
   the relevant subsystem spec (design) first. If an example needs a behavior
   the specs do not define, add the spec before the example — never invent
   behavior silently.
3. **Stay true to the Xz surface.** Effect labels are `none`/`mut`/`io`/`chan`/
   `extern`. Only `@export` functions cross the ABI. `Result` is not
   C-representable. Check the Xz spec before asserting a compiler behavior.
4. **No silent degradation.** Never specify a lossy fallback; a value that
   cannot cross the boundary is a hard error.
5. **One canonical way.** Never introduce a second way to say something. Prefer
   the most explicit, most reviewable form and document it.

## The two-developer model

This repository is developed by two maintainers, each with a clear domain. See
[docs/06-collaboration.md](docs/06-collaboration.md).

| Developer | Domain | Local queue |
|---|---|---|
| ax1s-x1zz | FFI bridge, binding generation, compiler integration | `NEXT_ax1s.md` |
| imrubydev | Rails Engine, service DSL, developer experience | `NEXT_ruby.md` |

Rules for an AI assistant working here:

- **Pick the right queue.** A session started with `/next_ax1s` reads
  `NEXT_ax1s.md`; a session started with `/next_ruby` reads `NEXT_ruby.md`.
  Work only the queue you were started with.
- **Stay in your lane.** Do not edit a gem owned by the other developer without
  an explicit request; cross-domain changes are coordinated through an issue or
  PR first.
- **Author commits as the developer doing the work.** The acting developer's
  name and email are the commit author and committer.
- **Never commit machine-local files.** The local queues (`NEXT_*.md`), the
  `.local/` directory, tokens, and any per-developer tooling are gitignored and
  must stay that way.
- **Never commit secrets.** No tokens, no credentials, no environment files.

The private developer runbook (local commit tooling and per-developer setup)
lives in `.local/OPERATIONS.md`, which is gitignored. Read it before doing any
git operation; never commit it.

## Commit rule

**Commit continuously and autonomously, in the smallest coherent unit, as soon
as one completes. Do not wait for the user to ask.**

- One logical change = one commit. A spec gap, a doc fix, and a roadmap update
  are three commits, not one.
- "Smallest coherent unit" means the change is internally consistent and
  complete: links resolve, no stale cross-references, no half-edits.
- Commit messages state the decision, not the file list:
  `Pin the bridge to the compiler version`, not `Update docs`.
- Never bundle unrelated edits, and never commit secrets.

## Before committing

- Run `git status`, `git diff`, and `git log --oneline -10`; stage only the
  intended files.
- Verify consistency: no dangling links, no stale examples, no contradictions
  between the PRD, architecture, and subsystem specs.
- Confirm the commit author is the developer who did the work (see
  `.local/OPERATIONS.md` for the exact command).

## Language and style

- Docs are in English, written for a reviewer of AI-written code.
- No emojis. No comments in code that restate the code.
- Keep doc changes tight: a new rule is one section, one example, one rationale
  — not an essay.
- The user writes in Korean; respond in Korean unless the user switches.
