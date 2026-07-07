# Parallel tracks: compiler (A), libraries/demos (B), C frontend (C), docs/website (D)

Work streams proceed in parallel, decoupled by a **pinned stable compiler**.
The point: A can rebuild and temporarily regress the compiler while B keeps
building libraries and demo apps against a known-good baseline, D writes the
public documentation against that same baseline, and C grows the C-language
frontend. (C grew on an isolated branch until it merged at v80; all tracks now
work on `master`.)

Testing breadth is offloaded to **Track T** (continuous watcher + agentic
test manager) — see `devdocs/dev/track-t.md` for the deploy one-liner, the
"confirm native, offload the matrix" protocol, and the `twatch --status`
liveness rule every track uses before relying on the offload.

The user runs **several Claude agents at once** against this repo — one per
track. Most sessions are one track. **The track letter is a stable ID; always
say it with its name** (e.g. "Track C (C frontend)"). The letters were chosen so
**C = the C language** and **D = documentation** — do not read "Track C" as docs.

## Which agent am I? (track auto-detection)

At the start of a session, infer the track from the user's request:

- **Track A — compiler (Pascal).** Signals: compiler internals, codegen / IR /
  backends, a target (i386 / aarch64 / arm32 / xtensa / riscv / ESP), parser /
  lexer / ABI / ELF, bootstrap / self-host / fixedpoint / `make stabilize`,
  fixing a compiler bug, adding a *language* feature, `compiler/**` (shared
  internals). Works on `master`.
- **Track B — libraries/demos.** Signals: `lib/rtl` / `lib/pcl`, `examples/**`,
  writing or fixing a *library* (JSON, hashing, `IntToStr`, `Copy`, collections),
  demo apps, `make lib-test` / `make demos`, a ticket tagged "(library)". Works
  on `master`.
- **Track C — C frontend (cfront).** Signals: the C-language frontend
  (`compiler/clexer.inc`, `cparser.inc`, `cpreproc.inc`, C-exclusive C→IR
  lowering), `lib/crtl`, compiling C programs (tiny-regex / lua / sqlite).
  **Works on `master`** (merged at v80; the old `feat/cfront` worktree is retired).
- **Track D — docs/website.** Signals: user documentation, getting-started /
  install / tutorial / language-reference prose, the website / landing copy,
  `docs/**`, "document feature X", "write the docs for". Prose only — no
  code changes. Works on `master`.

If the request is genuinely ambiguous, **ask**: "Am I on track A (compiler), B
(libraries/demos), C (C frontend), or D (docs/website) this session?" Don't guess
when unsure — the tracks have opposite rules about rebuilding the compiler and
where they work.

Once known, follow that track's section below. Lanes are soft (see the end), so
crossing over is allowed when a task needs it — but start from the inferred
track's defaults.

## The boundary

```
            stabilize          pin              compile with
  track A ──────────▶ vN ──────────▶ pinned ──────────────▶  track B
 compiler/**     (latest->vN)    (pinned->vN)              lib/**, examples/**
                 checkpoint      blessed-for-B
```

Two pointers in `stable_linux_amd64/default/`:

- **`latest`** → the newest recorded checkpoint. `make stabilize` moves it on
  every run. Bookkeeping; B does *not* follow it.
- **`pinned`** → the version blessed for track B. Moves only when A runs
  `make pin` (default = current `latest`, or `make pin VERSION=N`). Audited in
  `pin.log`.

- **`$(PXX_STABLE)`** = `stable_linux_amd64/default/pinned` (override per build:
  `make lib-test PXX_STABLE=stable_linux_amd64/default/vN`).
- This decouples *recording* a stable from *handing it to B*: A can checkpoint
  freely; B's ground only shifts on a deliberate `make pin`. `pxx-stable-check`
  tells A when `latest` is ahead of `pinned` (a checkpoint waiting to be blessed).
- Current platform (x86-64) only. Cross-compile is a later concern; the cross
  suites (`make test-i386 / test-aarch64 / test-arm32 / cross-bootstrap`)
  discover any per-target gaps after the fact.

## Track A — compiler

Owns (ideal): `compiler/**`, and the compiler / cross / esp / bootstrap /
stabilize parts of the `Makefile` and `test/`.

Publishing a new baseline, when a feature B needs lands:

```sh
make stabilize        # runs `make test` + 4-iteration fixedpoint, then records:
                      #   stable_linux_amd64/default/v{N+1}, latest -> vN+1,
                      #   last.sha256, history.log (ts, vN, sha, commit, subject)
make pin              # bless it for B: pinned -> latest (or VERSION=N), -> pin.log
git add stable_linux_amd64 && git commit -m "chore(stable): record vN, pin for B"
```

`make stabilize` only records a checkpoint (moves `latest`); it does **not**
touch `pinned`, so B is unaffected until you `make pin`. Bless deliberately when
a feature B is waiting on has landed. `history.log` is the checkpoint changelog;
`pin.log` records each blessing. Roll back the working compiler with `make revert
VERSION=N`; move B back with `make pin VERSION=N`.

The **authoritative gate is unchanged**: `make test` + self-host fixedpoint.
A feature is not "done" until it passes that. `make stabilize` will not record a
baseline that fails the gate.

`make test` (and therefore `stabilize`/`pin`) is **FPC-free** — it self-hosts off
the existing `compiler/pascal26`. FPC-dependent checks (compliance + the host
asm-emit oracle) live in `make test-fpc`, a release/CI postcheck, not the daily
gate. A fresh checkout seeds the working binary with `make seed-from-stable` (no
FPC); only a pure-source build with no committed binary needs `make bootstrap`.
See **`devdocs/dev/fpc-optional-workflow.md`**.

## Track B — libraries and demos

Owns (ideal): `lib/**`, `examples/**`, new `test/lib_*`, and the `lib-test` /
`demos` `Makefile` block. Always compiles with `$(PXX_STABLE)`, never rebuilds
the compiler.

```sh
make pxx-stable-check   # shows pinned vs latest; notes if a newer stable awaits blessing
make lib-test           # curated GREEN smoke (may hard-fail; keep it green)
make library-suite      # Track-B library suite: green gate + non-gating discovery
make demos              # compile-smoke dashboard for every example (exit 0)
```

`lib-test` / `library-suite-green` are the curated green library gate. Keep them
green. `library-suite-discovery`, `c-interop-devtest`, and `demos` are discovery
dashboards. When they surface missing or bugged library / language support
(e.g. a demo needs `Copy` or `IntToStr`, or a parse error), **file a ticket** in
`devdocs/progress/backlog` rather than treating the red as a hard failure.

Write Track B libraries platonically: prefer clear, idiomatic Pascal and the API
shape the library should have. If the pinned compiler rejects valid source or
miscompiles it, do **not** add compiler-appeasement workarounds to the library.
Leave the platonic code in place, add/keep the focused test even if it fails, and
file a Track A bug ticket with the exact compiler error or misbehavior.

## Track C — C frontend (cfront)

Owns: the **C-language frontend** — `compiler/clexer.inc`, `cparser.inc`,
`cpreproc.inc`, the C-exclusive C→IR lowering, `lib/crtl` (the C runtime), and C
tests. Goal: compile real portable C (tiny-regex → lua → sqlite); roadmap in
`devdocs/progress/backlog/feature-c-desktop-lua-sqlite-path.md`.

**Works on `master`** — like every other track. The C frontend merged to
`master` at **v80** (2026-06-26); the old `feat/cfront` worktree at
`../frankonpiler-cfront` is **retired**. The branch existed only while the C
frontend was destabilizing (it reseeds the compiler binary); now C *is* part of
the compiler, so it lives on `master`, protected by the same pin boundary every
track relies on (B/D build on `pinned`, not HEAD, so an in-progress C change on
`master` HEAD can't break them until it is pinned).

> **Why the branch was retired.** A long-lived branch traded one risk
> (destabilizing A/B/D's ground) for several worse ones that bit at merge time:
> token-enum and AST-node-number collisions (both tracks numbered into the same
> space independently), a cross-include forward-reference that only the FPC build
> caught, and "tested-locally ≠ what-was-pushed" drift. On `master` those surface
> immediately, in review, against the live numbers — not in a big-bang merge.

The load-bearing boundary with Track A is **unchanged** (it never depended on the
branch — it's a file-ownership rule):

- **C owns only the C-specific frontend files** (`clexer.inc`, `cparser.inc`,
  `cpreproc.inc`, C→IR lowering, `lib/crtl`, C tests). Shared compiler internals
  — AST node kinds, IR ops, `symtab` structures, `defs.inc`, `lexer.inc`,
  `parser.inc`, backend codegen (`ir_codegen*`), ABI, ELF — are **Track A's**.
- **Need a new AST node / IR op / symtab field / token / backend change?** →
  **file a Track A ticket;** do not edit the shared file under Track C. A
  implements it, gates it (`make test` + self-host), and `make pin`s it. This is
  exactly what stops the node-number/token collisions a branch let slip through.
- **Land only green;** big destabilizing work goes behind a flag or lands
  incrementally — never a long-lived branch.

C's gate: C tests green (gcc/tcc stdout-equality oracle) + self-host
byte-identical + cross-bootstrap.

### Combined-track assignment (one agent on two tracks)

The user may assign a single agent **two tracks at once** ("you are Track A *and*
C"). Then:

- The tracks stay **distinct** — own files, own gates, own ticket trail.
- A shared-code change is **still filed as a Track A ticket** (traceability — the
  board still shows what shared internals moved and why).
- But the **same agent may resolve its own ticket**, because the user has
  confirmed no *other* agent holds Track A concurrently, so the hand-off exists
  only to prevent collisions that can't happen here. File → self-resolve, instead
  of file → hand-off.
- The instant the agent is single-track again, revert to file-and-hand-off.

## Track D — documentation (user / website)

Owns: `docs/**` — the **user-facing** documentation, authored as Markdown and
**published to the website straight from git** (the site pulls the repo and
renders `docs/`; no separate docs repo, no generated artifacts checked in by
D). Typical content: getting-started, install, language reference, the standard
library / RTL reference, tutorials, FAQ, and the public landing copy.

Strict boundaries:

- **Prose only. D never edits `compiler/**` or `lib/**`** (or `Makefile` build
  logic). It does not rebuild the compiler — examples are compiled against
  `$(PXX_STABLE)` to verify they work, nothing more.
- **Not the internal docs.** `devdocs/dev/**` (this file, design notes) and
  `devdocs/progress/**` (the agent board / tickets) are A/B/C territory, not website
  material. D stays in `docs/**`.
- **Verify, don't invent.** Every code snippet in the docs should actually compile
  and run on the pinned compiler — paste real output, don't guess behaviour. A
  doc example is a mini conformance test.
- **Found a gap while documenting** (a feature that doesn't work as it should, a
  missing library, a confusing error) → **file a ticket** in
  `devdocs/progress/backlog` (tag the track it belongs to) rather than fixing code.
  Document what *is*, note the gap, move on.

D's "gate" is light: internal consistency (no dead links, examples compile), and
the published tree under `docs/` builds whatever static-site generator the
website uses (kept generator-agnostic — plain Markdown + front-matter so any of
mkdocs / Docusaurus / Hugo / a custom puller can render it).

## Lanes are soft, not walls

The split above is the *ideal*, not a fence. This is a dialect:

- A may touch `lib/**` when a builtin or a compiler test needs it (ideally only
  the builtin libs, but not exclusively).
- B may be asked to bug-hunt or advise on the compiler.

Expect a grey zone. The rule that matters: **the authoritative gate is `make
test` + self-host fixedpoint**, and a fresh `make stabilize` is what hands B a
compiler with new features. Coordinate through commits on `master` and the
`history.log` baseline; keep cross-edits to the shared `Makefile` inside each
track's fenced section to avoid collisions.

## Shared checkout — coordination

**All tracks (A, B, C, D) share the same checkout** on `master` (no clones, no
worktrees — C's `feat/cfront` worktree was retired when it merged at v80). The
rules below are for that shared `master` checkout:

- **Commit early and often, in small units.** Uncommitted edits are the only
  thing the other agent can stomp; committed work is safe.
- **Stay in your lane's files.** A → `compiler/**` (shared internals); B →
  `lib/**`, `examples/**`, `test/lib_*`; C → `compiler/c{lexer,parser,preproc}.inc`
  + C→IR lowering, `lib/crtl`, C tests (but shared `compiler/**` internals are
  A's — file a Track A ticket); D → `docs/**`. File overlap is then near
  zero. The shared `Makefile` is fenced per track.
- **`git pull --rebase` before you push**, and push promptly after committing —
  the other agent may have pushed in between. Resolve in your own files.
- **Push freely when stable; you don't need to ask.** History is reversible, so a
  push of a green, lane-gated state is always safe. The bar is: your lane's gate
  passes (A = `make test` + self-host byte-identical; B = `make lib-test` /
  `demos`) and nothing half-finished is committed. Do NOT push a known-broken or
  mid-refactor tree, and never sweep the *other* agent's uncommitted in-flight
  work into your push — push only what you committed (`git commit -- <paths>`).
- **`git log --oneline -5` at session start** to see what the other track just
  landed (e.g. a new stable `vN`, a freshly closed ticket).
- **`BOARD.md` never conflicts.** It is generated from the ticket files and both
  agents regenerate it constantly, so it carries a `merge=ours` attribute
  (`.gitattributes`) — git keeps the current side on a merge/rebase instead of
  raising a conflict, and the content self-heals on the next `tools/progress.sh
  board-md`. This needs a **one-time per-checkout** config (not committable):
  `git config merge.ours.driver true`. Run it once if you ever see a BOARD.md
  conflict; then just regenerate the board before pushing.
- B never needs to rebuild the compiler; A's in-progress `compiler/pascal26` is
  irrelevant to B because B uses `$(PXX_STABLE)`. So a half-built compiler binary
  in the tree does not block B.
  - **EXCEPTION — runtime-read builtin RTL.** The pinned binary still reads
    `compiler/builtin/*.pas` (e.g. `builtinheap`) from the **live tree** at
    runtime, so A's uncommitted WIP there *does* break B. Until that is frozen
    with the binary (bug-pinned-stable-reads-live-builtin-rtl), this is a
    **halt-and-wait** grey zone: if `compiler/builtin/**` shows uncommitted
    edits, the other agent stops and waits rather than working around or
    stomping. Safer to halt than to make a mess.

## Future consideration: split dev trees (not adopted yet)

Today both agents share one working tree on `master`. It works because the lanes
barely overlap and we commit in small units. But the coupling we *do* hit — the
runtime-read builtin RTL grey zone above, the stable-binary re-pin handshake, the
"don't sweep the other agent's uncommitted work" caveat — all stem from the
single shared checkout.

An alternative worth weighing when the friction justifies it: **per-concern dev
trees** — `compiler`, `libs`, `demos` (roughly Track A / Track B-rtl /
Track B-apps) — each its own worktree or clone, with an **auto-merge / conflict
resolver** integrating them back to `master`. The lanes are already file-disjoint
enough that most merges would be trivial (different directories); a small merge
driver could auto-resolve the few shared touchpoints (`Makefile` fences, `BOARD.md`
regeneration, the `stable_linux_amd64/` pin bump) deterministically.

The mechanism is **`git worktree`**, not clone: `git worktree add ../fk-X -b X`
makes a second working dir on its own branch that **shares the one `.git` object
store** — no disk duplication, and a commit in one tree is visible to the others
with no fetch (shared refs). One rule: a given branch can be checked out in only
one tree at a time (git refuses otherwise), so each tree = a distinct branch.
`clone --shared`/`--reference` also shares objects but adds a gc-on-source
corruption footgun; plain `clone` duplicates the whole store. So worktree is the
cheap option if this is ever adopted. Cleanup is `git worktree remove ../fk-X`.

### Per-*feature* worktree (the lighter, on-demand use)

The standing A/B split above is the heavyweight framing. The cheaper, undersold
use is a **throwaway worktree for a single large or risky arc** — e.g. the DWARF
debug-info tiers or the optimizer pass framework — that would otherwise churn
`master` mid-flight or sit half-finished across many commits. Pattern:

```
git worktree add ../fk-dwarf -b feature-dwarf   # isolate the arc
# ... build, commit freely on the branch, never destabilising master ...
git worktree remove ../fk-dwarf                  # after merge to master
```

This stays inside "work on `master`" in spirit: the feature branch is short-lived
and merges straight back, you just don't expose half-built intermediate states on
`master` while the arc is in motion. Reach for it **only** when an arc is big
enough that its in-progress tree would block the other agent or muddy bisect —
small lane-local work still goes directly on `master` as today. No standing
process, no merge driver; spin one up, fold it back, delete it.

Trade-off: it removes the shared-checkout stomp risk and lets each agent push its
own tree without coordination, at the cost of a merge layer and losing the
zero-latency "see the other agent's commit instantly" property. **Not adopted** —
recorded here so the option is on the table, not rediscovered cold. Revisit if
shared-tree contention (halt-and-wait on builtin RTL, re-pin stalls) starts
costing real time.


## Iteration pins: `make stabilize-fast` (2026-07-03)

`make stabilize-fast` = the everyday iteration pin: a curated smoke subset
(`test-smoke`, regression-prone surfaces + the full self-host byte-identity
chain) instead of the full suite, then the same recording step. ~18s wall.
POLICY: fine for iteration; run full `make stabilize` before pushing a batch
of work, for milestone pins, releases, and anything touching
codegen/ABI/ELF. `make pin` blesses whichever was recorded last, as before.
New features append a case to `test-smoke` AND their full-suite test.
