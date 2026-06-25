# Parallel tracks: compiler (A), libraries/demos (B), C frontend (C), docs (D)

Work streams proceed in parallel, decoupled by a **pinned stable compiler**.
The point: A (Pascal compiler) and C (C frontend) can rebuild and temporarily
regress the compiler while B keeps building libraries and demo apps against a
known-good baseline, and D writes the public documentation against that same
baseline.

> **Track C/D were swapped.** Track **C is now the C frontend** (compiling C
> source); Track **D is documentation** (`docs/site/**`). Older tickets/commits
> that tag the C-frontend work `[D]`/`track-d` or docs `[C]`/`track-c` predate the
> swap — read them by content, not the stale tag.

The user runs **several Claude agents at once** against this same repo/branch —
one per track. Most sessions are one track.

## Which agent am I? (auto-detection)

At the start of a session, infer the track from the user's request:

- **Track A — compiler core.** Signals: compiler internals, codegen / IR /
  backends, a target (i386 / aarch64 / arm32 / xtensa / riscv / ESP), parser /
  lexer / ABI / ELF, bootstrap / self-host / fixedpoint / `make stabilize`,
  fixing a compiler bug, adding a *Pascal language* feature, `compiler/**` files
  (the Pascal frontend, shared IR, backends).
- **Track B — libraries/demos.** Signals: `lib/rtl` / `lib/pcl`, `examples/**`,
  writing or fixing a *library* (JSON, hashing, `IntToStr`, `Copy`, collections),
  demo apps, `make lib-test` / `make demos`, a ticket tagged "(library)".
- **Track C — C frontend.** Signals: compiling **C source**, `compiler/clexer.inc`
  / `compiler/cparser.inc` / `compiler/cpreproc.inc`, `test/*.c` fixtures,
  `c-interop-devtest`, the `feat/cfront` branch, the tiny-regex → lua → sqlite
  path. C-body lowering rides the shared IR → edits the compiler binary like A.
- **Track D — docs/website.** Signals: user documentation, getting-started /
  install / tutorial / language-reference prose, the website / landing copy,
  `docs/site/**`, "document feature X", "write the docs for". Prose only — no
  code changes.

If the request is genuinely ambiguous, **ask**: "Am I on track A (compiler core),
B (libraries/demos), C (C frontend), or D (docs/website) this session?" Don't
guess when unsure — A and C edit the compiler binary (self-host gate), B never
rebuilds it, and D must not touch code.

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
See **`docs/dev/fpc-optional-workflow.md`**.

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
`docs/progress/backlog` rather than treating the red as a hard failure.

Write Track B libraries platonically: prefer clear, idiomatic Pascal and the API
shape the library should have. If the pinned compiler rejects valid source or
miscompiles it, do **not** add compiler-appeasement workarounds to the library.
Leave the platonic code in place, add/keep the focused test even if it fails, and
file a Track A bug ticket with the exact compiler error or misbehavior.

## Track C — C frontend (compiling C source)

Owns: the **C-source compilation path** layered onto the same compiler —
`compiler/clexer.inc` (C lexer), `compiler/cparser.inc` (C parser + body
lowering), `compiler/cpreproc.inc` (C preprocessor), the `test/*.c` fixtures, and
the `c-interop-devtest` suite. Worked on the isolated **`feat/cfront`** branch /
worktree so its in-progress compiler edits don't destabilise `master`.

The leverage: the C frontend emits the **same shared IR** the Pascal frontend
does, so all six backends, ELF, and the ABI come for free; C `extern` maps onto
the existing dynamic-link / external-symbol path (`printf`/`malloc`/`fopen`
resolve to libc). The header-import half (typedef/struct/union/enum, POD layout,
extern decls, integer macros) is mature; the active work is the **body** half
(expressions, statements, multi-function, then setjmp/longjmp + varargs-define).

Rules — same compiler-binary discipline as Track A:

- **Gate = `make test` + self-host fixedpoint (byte-identical).** Because C-body
  lowering goes through the shared IR, a C-frontend change edits the compiler
  binary; a half-applied one breaks the self-host gate (CRITICAL, like A).
- **Keep body lowering in the shared IR, not per-target codegen** — cross
  regressions (i386/arm32/aarch64/riscv32/xtensa) otherwise surface late. Run the
  multi-target harness, not just x86-64.
- **Oracle = gcc/tcc stdout-equality** on deterministic int/string output.
- **The clexer is shared with header import** — collapsed multi-char operators are
  relied on by `CEvalConstExpr`; update the const-evaluator in the same change.
  Keep the `->` → `tkDot` mapping. Mind `MAX_UCLASS`/`MAX_UFIELD` pressure (C
  structs share Pascal's tables; preserve opaque-fallback guards).
- **Shared-IR touch-points** (e.g. `AN_EXIT`→Halt, a future `AN_TERNARY` /
  break-only switch scope) are recorded in
  `track-a-c-frontend-shared-ir-touchpoints` for Track A to reconcile at merge.

North star: compile real portable C — `feature-c-desktop-lua-sqlite-path`
(tiny-regex warmup → lua → sqlite). Note `library_candidates/` (the staged
upstream C sources) lives in the **master checkout**, not the `feat/cfront`
worktree — stage lua/regex there before attempting M1/M4.

## Track D — documentation (user / website)

Owns: `docs/site/**` — the **user-facing** documentation, authored as Markdown and
**published to the website straight from git** (the site pulls the repo and
renders `docs/site/`; no separate docs repo, no generated artifacts checked in by
D). Typical content: getting-started, install, language reference, the standard
library / RTL reference, tutorials, FAQ, and the public landing copy.

Strict boundaries:

- **Prose only. D never edits `compiler/**` or `lib/**`** (or `Makefile` build
  logic). It does not rebuild the compiler — examples are compiled against
  `$(PXX_STABLE)` to verify they work, nothing more.
- **Not the internal docs.** `docs/dev/**` (this file, design notes) and
  `docs/progress/**` (the agent board / tickets) are A/B/C territory, not website
  material. D stays in `docs/site/**`.
- **Verify, don't invent.** Every code snippet in the docs should actually compile
  and run on the pinned compiler — paste real output, don't guess behaviour. A
  doc example is a mini conformance test.
- **Found a gap while documenting** (a feature that doesn't work as it should, a
  missing library, a confusing error) → **file a ticket** in
  `docs/progress/backlog` (tag the track it belongs to) rather than fixing code.
  Document what *is*, note the gap, move on.

D's "gate" is light: internal consistency (no dead links, examples compile), and
the published tree under `docs/site/` builds whatever static-site generator the
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

Both agents work the **same checkout** on `master` (no worktrees, no clones, per
the user's repo workflow). To avoid clobbering each other:

- **Commit early and often, in small units.** Uncommitted edits are the only
  thing the other agent can stomp; committed work is safe.
- **Stay in your lane's files.** A → `compiler/**`; B → `lib/**`, `examples/**`,
  `test/lib_*`. File overlap is then near zero. The shared `Makefile` is fenced
  per track.
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
