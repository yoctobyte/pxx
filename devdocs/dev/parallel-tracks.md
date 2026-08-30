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
  suites discover any per-target gaps after the fact — **as Track T's sweep
  against your pushed sha, not as something you run.** Those targets are denied
  by the same hook as the rest of the suite family.

## Track A — compiler

Owns (ideal): `compiler/**`, and the compiler / cross / esp / bootstrap /
stabilize parts of the `Makefile` and `test/`.

Publishing a new baseline, when a feature B needs lands:

```sh
make stabilize-fast   # ~35s. THE DEFAULT (see the correction below). self -> next
                      #   -> fixedpoint, then records:
                      #   stable_linux_amd64/default/v{N+1}, latest -> vN+1,
                      #   last.sha256, history.log (ts, vN, sha, commit, subject)
make pin              # bless it for B: pinned -> latest (or VERSION=N), -> pin.log
git add stable_linux_amd64 && git commit -m "chore(stable): record vN, pin for B"
```

Plain `make stabilize` runs the same recording, preceded by the full suite and a
4-iteration fixedpoint — ~25 minutes with the repo lock held. It is for a
RELEASE, or when Track T is *proven* down, not for a pin.

`make stabilize` only records a checkpoint (moves `latest`); it does **not**
touch `pinned`, so B is unaffected until you `make pin`. Bless deliberately when
a feature B is waiting on has landed. `history.log` is the checkpoint changelog;
`pin.log` records each blessing. Undo a blessing with `make revert` (steps back
one pin; `make revert VERSION=N` goes straight to a named one). It restores every
tracked file under the stable dir from the commit that pinned that version, so
`pinned`, `VERSION` and `pin.log` come back byte-for-byte, and it leaves the
result staged for you to commit. `make pin` takes no `VERSION=`.

> ## Corrected 2026-08-30 (frankD) — the gate this section names is refused
>
> This said *"the **authoritative gate is unchanged**: `make test` + self-host
> fixedpoint. A feature is not 'done' until it passes that."* **CLAUDE.md is the
> single source of truth for gating, and it now says otherwise.** The per-fix
> loop is `make compiler/pascal26` (~12s, and it *is* the byte-identical
> self-host fixedpoint) plus your repro; `tools/gate.sh quick` is optional per
> fix and required only before a pin. Breadth — full suites, cross targets, the
> corpus — is **Track T's job**, run against your pushed sha and returned
> asynchronously.
>
> This is not advice you may weigh against the text above: `make test` is **denied
> by a PreToolUse hook** (`.claude/hooks/no-full-suite.sh`), as are the heavy
> `gate.sh` and `testmgr` tiers and the cross suites named earlier in this file.
> An agent following this page's ladder meets a refusal, not a gate.
>
> The same correction applies to the pin recipe above: **`make stabilize-fast &&
> make pin` (~35s) is the default**, and full `stabilize` is for a release. A pin
> holds the repo lock, so every other lane and the human wait for it — and the
> one property a bad pin could poison for everyone, a compiler that cannot
> reproduce itself, is exactly what `stabilize-fast`'s self→next→fixedpoint chain
> proves.
>
> **This page is where CLAUDE.md sends every agent** — *"Full protocol … is in
> `devdocs/dev/parallel-tracks.md`. Read it before starting your track."* — which
> makes it the highest-consequence copy of a stale gate in the tree, and the
> reason it survived is the ordinary one: the rule it states is **tighter** than
> the rule that replaced it, so obeying it wasted ten minutes and produced
> nothing wrong. Nobody reports that.

The gate `make stabilize` enforces is **FPC-free** — it self-hosts off the
existing `compiler/pascal26`. FPC-dependent checks (compliance + the host
asm-emit oracle) live in a separate release/CI postcheck target, not in any
daily gate. A fresh checkout seeds the working binary with `make seed-from-stable` (no
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
[[feature-c-desktop-lua-sqlite-path]].

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
  backend codegen (`ir_codegen*`), ABI, ELF — are **Track A's**. (`pasparser_*.inc`
  became **Track P's** on 2026-08-20; `lexer.inc` is still shared.)
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

## Work-tag: compat (reference compatibility)

`compat` is a work-tag (no letter, like X's mirror image): "behave like the
reference implementation" for any frontend — FPC/Delphi for P, gcc/ISO C for
C, rustc for R, Zig for Z. It spans compiling real-world code (fgl, Synapse,
FPC itself, zlib whose compressed OUTPUT is byte-identical to a gcc-built
zlib's — behavioral parity, NOT gcc codegen parity; see the precision note in
CLAUDE.md) down to parity diagnostics, the
per-feature strict flags (`--strict-case`, `--strict-overload`) and `{%FAIL}`
conformance tests. Compat tickets stay in the ranked queue (the tag carries no
priority — the `prio:` field does), inherit the owning frontend's file-lane
and gate, and use the `compat-<lang>-*` slug convention. Escape rule: a compat
finding that means silent wrong behavior is promoted to a normal `bug-` ticket
in the owning lane. PXX's dialect stays deliberately lax by default —
FPC-parity strictness is opt-in per feature, and the conformance sweep
(`tools/run_pascal_conformance.sh`) runs with the strict flags on; deliberate
divergences are documented as `dialect-pass` entries in
`test/pascal-conformance/pxx.skip`.

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
- **Push OFTEN; you don't need to ask.** Since Track T (see
  `devdocs/dev/track-t.md`), the full matrix runs offloaded against
  origin/master — unpushed work is untested work. The bar per push: native
  confirm (`tools/testmgr.py --tier quick` + self-host fixedpoint for compiler
  changes) and nothing half-finished committed; Track T catches the breadth
  and reports per-SHA. Only when `twatch --status` says T is down does the old
  bar return (your lane's full gate before risky pushes). Do NOT push a
  known-broken or mid-refactor tree, and never sweep the *other* agent's
  uncommitted in-flight work into your push — push only what you committed
  (`git commit -- <paths>`).
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
POLICY: fine for iteration. Full `make stabilize` is for PINS, not pushes —
milestone pins, releases, anything touching codegen/ABI/ELF that will move
`pinned`. Ordinary pushes are gated by the native confirm + Track T offload
(see the push norm above), not by stabilize. `make pin` blesses whichever
was recorded last, as before.
New features append a case to `test-smoke` AND their full-suite test.


---

# Track charters — the long form

**Moved out of CLAUDE.md on 2026-08-30**, verbatim. CLAUDE.md carries the
framing plus the one-line-per-track summaries; this is the full description of
each lane, kept because it holds the *reasoning* behind the letters — what a
lane owns, why the set is deliberately small, and the file-lane / work-tag
distinction. Read it when a lane question actually needs settling, not at
session start.

It was 302 of CLAUDE.md's 938 lines, describing every track a second time
alongside the one-liners that were already there. The duplication was the
cost: every agent loaded both, every session, before doing any work.
Rationale: `devdocs/dev/coordination-overhead-2026-08-30.md`.

## Tracks — coordination lanes, not a taxonomy

The user runs **multiple Claude agents at once** on this repo. A track is a
**lane to keep concurrent agents from clobbering each other's files, plus the
gate each must stay green** — it is NOT an ontology of the codebase. So:

- **Default: one lane per session.** Infer a single track from the request and
  stay in it. This is for *your context*, not git — juggling two topics (say the
  Pascal frontend and the Rust frontend at once) makes you reason worse, even
  though their source rarely collides. Mergeable ≠ free to mix: the cost is
  context confusion, not merge conflicts.
- **Several tracks only when the user explicitly assigns them** ("you're A+C").
  Then it's fine — you're free to touch all of them, you just respect every gate
  you span, and a shared-internals change is still filed as a Track A ticket
  (combined-track note below). The letters otherwise only matter *when* two
  agents run at once and must not fight over the same file.
- **Don't invent new letters.** No Track L for libraries, no "LC" for C
  libraries. The set below is deliberately small; resist splitting it finer.
- **Two axes: lanes vs tags.** The letters mix two kinds of thing, and that's
  fine once you see it. **File-lanes** (exclusive, collision-avoidance): **A**
  core, **B** libs/demos, **C/N/P/R/Z** frontends — these answer "who owns this
  file when two agents run at once." **Work-tags** (human grouping, compose
  freely, each *inherits* a file-lane): **O** optimization (owned by A), **E**
  examples/apps (owned by B), **F** floating point (owned by whoever owns the
  file), **S** eSpressif/SoC (owned by A+B), **T**
  testing, **D** docs, **X** experimental. A
  tag is not a new file-lane — "Track O" work still lands under A's gate, "Track
  E" under B's. So pick a new letter on the right axis: a new *place code lives* →
  new lane (rare, resisted); a new *kind of work* over existing files → tag.
- **X is a TAG, not a lane: experimental.** Tracks R (Rust) and Z (Zig) are
  also X — their tickets live in `devdocs/progress/experimental/` (never
  ranked by `next`/`ready`; see that folder's README for the upscale rule).
  An X-tagged track keeps its own letter, files, and gate; X only says
  "optional, never a prio, pick up on user request or for fun". Reserved,
  unstaffed letter: **J** = JavaScript (currently routed through Track C —
  the QuickJS corpus ticket — so J may never need staffing).
- **compat is a TAG (no letter): reference compatibility.** "Behave like the
  reference implementation" for any frontend — FPC/Delphi for P, gcc/ISO C
  for C, rustc for R, Zig for Z. One category spanning the whole spectrum:
  compiling real-world code (fgl, Synapse, FPC itself, zlib whose compressed
  OUTPUT matches a gcc-built zlib's byte for byte) down to parity diagnostics,
  strict-mode flags (`--strict-case`,
  `--strict-overload`) and `{%FAIL}` conformance tests. Mirror image of X:
  X = *more* than the spec (experimental, unranked); compat = *exactly* the
  spec (stays ranked — the tag carries no priority, the `prio:` field does:
  "Synapse must compile" can sit at 60 while conformance-diagnostic parity
  idles at 15-20). Inherits the owning frontend's file-lane and gate like
  every tag. Slug convention: `compat-<lang>-*`. Escape rule: a compat
  finding that means *silent wrong behavior* (e.g. an ignored directive
  producing wrong values) is promoted to a normal `bug-` ticket in the owning
  lane — the tag is for parity work, not a place to hide real bugs. PXX's own
  dialect stays deliberately lax by default; FPC-parity strictness lives
  behind per-feature strict flags, and the conformance sweep runs with them
  on (see pxx.skip's `dialect-pass` entries).
  **A strict flag's scope is COMPILATION, not death** (user, 2026-08-21):
  `--strict-fpc` / `--mimic-fpc` govern how source is compiled and how output is
  formatted — number rendering included — and may extend to cosmetic parity such
  as an RTTI type name. They do NOT govern how a program DIES: runtime-error
  numbers, exit codes and fault messages stay ours by default, with FPC's
  conventions opt-in behind the `--fpc-*-errors` flags. *"We seek LANGUAGE
  compliance, not error-handling compliance"* — so parity work whose subject is
  error REPORTING is low prio by that same call, the way float accuracy is low
  prio by Track F's.

  **We do not chase 100% FPC parity** (user, 2026-08-26): *"we don't strive to
  mimic FPC 100%. We just care for correct compiling pascal code, not emulating
  every behaviour."* This is the ceiling the two rulings above were each
  approaching from one side, stated once and generally. The bar a compat ticket
  must clear is now explicit:

  | the ticket says | verdict |
  | --- | --- |
  | real Pascal source compiles wrong, or not at all | **bug** — own lane, own prio, not compat |
  | real Pascal source compiles but *runs* wrong | **bug** — silent-wrong-behavior escape, as above |
  | FPC accepts a form we reject | **compat**, ranked by how much real code uses it |
  | we accept a form FPC rejects | **not a defect** — same call NilPy makes for CPython; note it in the divergences doc |
  | our diagnostic/message/error number differs | **defer** — error reporting, low prio by the ruling above |
  | our output *formatting* of a value differs | **F** if it's a float, else compat at low prio |
  | an observable that no compiling program can reach | **never** — close it `rejected/`, cite this row |

  The last two rows are where the backlog actually leaks. "FPC prints this
  differently" and "FPC's RTTI spells this name differently" are *not* on the
  path to compiling correct Pascal, and a ticket that cannot name a program
  whose behaviour changes is a `rejected/` ticket, not a low-prio one — parking
  it at prio 10 keeps it in the ranker's scan forever at zero value.

Two axes cut the repo, and the tracks follow them:

1. **Accepted languages (frontends)** — what the compiler *parses*: **P** Pascal
   (the full dialect — classes, generics, RTL semantics, *far* past the subset
   self-host needs), **C**, **N** Nil-Python, **R** Rust, **Z** Zig. Each is a
   whole language with its own tests; each lowers to the shared IR. (N/C are
   mainline and gated; R/Z are experimental — X-tagged, see below.)
2. **The core + everything around it** — **A** the language-agnostic machinery
   (AST/IR/backends/ABI/ELF/self-host), **B** libraries (all languages), **D**
   public docs.

The compiler is *written in* a thin Pascal subset, bootstrappable with FPC —
but that's incidental: it could have been written in C, Zig, or whitespace. "The
compiler is in Pascal" (Track A's impl) and "Pascal is a frontend" (Track P) are
different things. **Always pair the letter with its name** (e.g. "Track C (C
frontend)"). **At session start, infer your track from the request:**

- **Track A — compiler core (language-agnostic).** AST / IR / backends / a
  target / codegen / ABI / ELF, bootstrap / self-host / `make stabilize`,
  cross-target work, the shared `ir*.inc` / `symtab.inc` / `defs.inc` and the
  backends. The integrator: everything below the frontends, plus the self-host
  gate that blesses the stable binary all other tracks build on. Works on
  `master`.
- **Track B — libraries / demos (all languages).** `lib/rtl` (Pascal) · `lib/pcl`
  · `lib/crtl` (C) · future `lib/zrtl` (Zig), `examples/**`, writing or fixing a
  library (JSON, hashing, `IntToStr`, `Copy`…), demo apps, `make lib-test` /
  `make demos`, tickets tagged "(library)". Language-neutral by design — libs are
  split by *what they do*, never by source language. Works on `master`.
- **Track C — C frontend (cfront).** The C-language frontend
  (`compiler/clexer.inc`, `cparser.inc`, `cpreproc.inc`, C-exclusive C→IR
  lowering), `lib/crtl`, C tests. **Works on `master`** (as of v80, when the C
  frontend merged in — the old `feat/cfront` worktree is retired). Protected by
  the same pin boundary (B/D build on `pinned`, not HEAD).
- **Track D — documentation (user / website).** `docs/**` — the user-facing
  docs the website pulls straight from git and publishes (getting-started,
  language reference, tutorials, install, the public landing copy). Prose only:
  **never** touches `compiler/**` or `lib/**`. NOT the internal dev docs
  (`devdocs/dev/**`) or the agent board (`devdocs/progress/**`) — those belong to A/B.
  Works on `master`.
- **Track P — Pascal frontend (pfront).** The Pascal *dialect* as a language:
  syntax / semantics / new language features and their frontend bugs — a full
  frontend, peer of C/Z, not "the compiler's impl language." **P now owns its
  own parser files** (2026-08-20): the 37,249-line `parser.inc` was sliced into
  `pasparser_name` / `_class` / `_generic` / `_call` / `_lval` / `_expr` /
  `_stmt` / `_decl` / `_proc` / `_prog`, and the machinery that was never Pascal
  went with its real owner — `ast_arena.inc`, `inline_expand.inc`,
  `ast_syminfer.inc`, `dbg_filetable.inc` to **A**, and NilPy's ~200 forwards to
  **N** as `pyforwards.inc`. The map is at the bottom of
  `compiler/frontend_forwards.inc`.
  *Residual catch:* the LEXER is not carved out — Pascal still shares
  `lexer.inc` with A (and Pascal-facing `defs.inc` / `symtab.inc`), so **P and A
  must not edit `lexer.inc` concurrently** and the node/token-numbering
  discipline still binds. A `pas`lexer split is the remaining half. Anything
  below the frontend (IR ops, backends, ABI, ELF) is core A. Works on `master`.
- **Track R — Rust frontend (rfront).** The Rust-language frontend and its
  Rust→IR lowering, `lib/rrtl` (as it lands), Rust tests. Live work in
  `devdocs/progress/working/feature-rust-*`. Same rule as C/Z: own your frontend
  files; shared-internals change → **file a Track A ticket**. Works on `master`.
- **Track T — Tools & Testing (watcher, agentic test manager, fuzzers).** Owns
  `tools/testmgr.py`, `tools/twatch.py`, `devdocs/progress/tstate/**` and the
  report format — plus the **fuzzing tooling**: `tools/fuzz.sh` (mutation +
  cross-target differential), `tools/pasmith.py` / `tools/pasmith_run.py`
  (random Object Pascal generator + FPC differential driver), and any Csmith
  runs. T is "a tool used for testing", not "regression testing only": fuzzing
  is testing whose oracle is a second implementation rather than a recorded
  expectation, so it lands here. Face 1 = the standalone twatch daemon (any
  box, its own dedicated clone, publishes sparse per-SHA regression reports to
  `tstate/` ONLY — that's the watcher identity's whole write scope). Face 2 =
  an agent (supervised session or cron) that consumes tstate, files/updates
  regression tickets like any track agent, maintains the Track T codebase
  itself, and **fuzzes in spare cycles**.
  **T owns the TOOL, never the bug.** A fuzz/tstate finding is filed into the
  owning lane — IR/codegen → A, dialect/frontend → P, RTL/ansistring → B —
  exactly like a tstate NEW-RED. T does not fix the compiler.
  Once a watcher is live, dev tracks may gate pushes on `testmgr --tier
  quick` + self-host fixedpoint; the full matrix runs offloaded, so master
  MAY carry cross-target reds for hours — tstate is the truth, and a
  core-job red older than a day is a revert candidate. Gate for T's own
  tooling changes = `tools/testmgr.py --tier full` green.
- **Track E — examples & apps (formal category, file-owned by Track B).** Apps
  *built with* PXX, not PXX itself: demos, games, GUIs, IDEs (the current Pascal
  one and a future NilPy one are both just E apps — don't burn a letter per tool),
  and the portable-userland/shell showcase. Lives in `examples/**`, `lib/**`, app
  dirs = **Track B file-ownership + gate** (build with `$(PXX_STABLE)`, never
  rebuild the compiler; `make lib-test`/`demos`). A compiler/frontend gap an app
  forces → file it under the owning lane (Track A / the frontend). `feature-demo-`
  / `idea-demo-` slugs auto-tag E. Works on `master`.
- **Track O — optimization (formal category, implicitly Track A).** A
  cross-cutting *lane*, not a file set: codegen/runtime speed work —
  register allocation, `-O` passes, the heap allocator, anything chasing the
  emitted-code or alloc-path cost. Almost everything here edits Track A's shared
  ground (`ir_codegen.inc`, `symtab.inc`, the backends, `compiler/builtin/**`), so
  **an O ticket carries a Track A file-ownership tag and obeys A's rules**:
  self-host byte-identical gate, no-concurrent-edit with A. O is just the visible
  grouping so the optimization campaign reads as one lane (surfaced on the board
  like R/T; `feature-opt-*` slugs auto-tag O). New passes land behind `-O3` (a
  free tier — nothing gates `OptLevel>=3` yet) and promote to `-O2` per-pass only
  after the full gate; `-O2` stays the proven default. **Per-backend effort
  (peepholes, register allocator) = x86-64 + aarch64 only** — 32-bit is
  perf-irrelevant and ESP/xtensa's hot paths are hardware peripherals; shared-IR
  passes still help all targets free. Works on `master`.
- **Track S — eSpressif / SoC (formal category, file-owned by A and B).** The
  ESP32 family — ESP32, S2, S3, C3 — as one visible campaign: the xtensa and
  riscv32 backends, `lib/rtl/platform/esp/**`, the ESP-IDF profile
  (`--platform=esp`, `--esp-profile=bare`), and `examples/esp32/**`. Like **O**,
  this is a work-tag surfaced as its own lane, NOT a file-lane: every S ticket
  also carries its Track A (compiler internals — `ir_codegen_xtensa.inc`) or
  Track B (`lib/rtl/platform/esp`, `lib/crtl`, examples) ownership for collision
  rules, and obeys that lane's gate. It exists because ESP work is otherwise
  spread across A/B/E and reads as unrelated items, which is how it drifted.
  **ESP is not a Unix** — FreeRTOS gives tasks, not processes — so 33 PAL entry
  points are refused even under IDF (no fork/exec/wait/kill, no pipes, no cwd,
  no links, no stat, no mmap); sockets and basic VFS file I/O are what work. The
  letter reads as "SoC" as much as "eSpressif", so a future non-Espressif MCU
  target fits without renaming. `*-esp-*` / `*-xtensa-*` slugs auto-tag S.
  Works on `master`.

- **Track F — floating point (a work-tag, owned by whoever owns the file).** The
  owner assigned this letter on 2026-08-19, after stating the rule four times:
  **float accuracy is LOW PRIO by definition.** *"compiler syntax, segfaults, etc,
  all prio. floating point, especially when 'mostly ok' (apart performance or
  insignificant digits), very low prio."* Same shape as O/S/M — **not a file-lane**:
  an F ticket ALSO carries its A/B/C/N/P file ownership for collision rules and obeys
  THAT lane's gate, so `track: B+F`, `track: P+F`, `track: A+F` are the normal
  spellings, and the ranker resolves both letters (`normalize_track` accepts F, so a
  `B+F` ticket is a B ticket that is also F). **But `ready --track F` correctly prints
  nothing** — `ready`/`next` scan only `urgent`/`backlog`/`backlog_new`/`unfinished`
  (`working/` is a live lock and is deliberately NOT ranked), and F
  tickets live in `float/`. **Parking and rankability are the same switch: you get the
  invisibility or the filter, not both.** To see the F set, list `devdocs/progress/float/`.
  **What is F — float MATH and float FORMATTING alike** (owner, same day: *"this
  implies both floating point math and formatting issues"*): ulps, rounding,
  subnormals, edge-of-range, correctly-rounded-vs-fast tiers, FPC/CPython numeric
  parity, precision of a float TYPE — and the whole rendering side, `Write`/`Writeln`
  of a real, `FloatToStr`/`Str`, digit counts, exponent form, and any *performance*
  work whose subject is float. Today's `WriteFloat` cluster would have been F end to
  end; it is the exact drain the letter exists to stop.
  **What is NOT F — rank the mechanism, never the datatype.** A ticket does not
  become F by containing a `Double`. A crash, a hang, a wrong signature, a
  control-flow or codegen bug that merely lives in float code, or a **missing**
  function a working CPython/FPC program calls — all stay ordinary bugs in their own
  lane at their own prio. Note the line moved once the owner broadened F to
  formatting: a badly RENDERED float is F even when the rendering is grossly wrong,
  because rendering is the subject. What is never F is a defect whose subject is the
  MECHANISM and whose float content is incidental. Mis-tagging in the F direction is how a
  real bug disappears, so when it is a close call it is NOT F.
  **Parking:** F tickets live in `devdocs/progress/float/`, which `ready`/`next`
  never scan (they read only `urgent`/`backlog`/`backlog_new`/`unfinished`). Nothing
  there is ranked or dispatched; it is picked up on explicit request, or for fun.
  Charter and the escape rule: `devdocs/progress/float/README.md`.
- **Track Z — Zig frontend (zfront).** The Zig-language frontend, greenfield:
  future `compiler/zlexer.inc`, `zparser.inc`, Zig-exclusive Zig→IR lowering,
  `lib/zrtl`, Zig tests. **Works on `master`**, under the same pin boundary as C.
  Same rule as C: own your frontend files; a shared-internals change (new AST
  node / IR op / symtab field / backend / anything in `lexer.inc`,
  `ir*.inc`, `symtab.inc`, `defs.inc`, the backends) → **file a Track A ticket**,
  do not edit it under Track Z. Gate = Zig tests green + self-host byte-identical
  + cross. Land only green; destabilizing work behind a flag or incremental,
  never a long-lived branch.
- **Track N — Nil-Python frontend (npyfront).** The Nil-Python language frontend —
  `compiler/pylexer.inc`, `compiler/pyparser.inc`, Python→IR lowering, `.npy`
  tests. **Mainline** (peer of C, not experimental like R/Z): it has its own
  carved-out files AND a gated suite (`make test-nilpy`, managed + frozen; real
  coverage — SQLite CRUD, classes, variants, string methods). Works on `master`,
  under the same pin boundary as C. Same rule as C/Z: own your frontend files; a
  shared-internals change (new AST node / IR op / symtab field / backend / anything
  in `lexer.inc`, `ir*.inc`, `symtab.inc`, `defs.inc`, the backends)
  → **file a Track A ticket**, do not edit it under N. Gate = `test-nilpy` green +
  self-host byte-identical + cross. Land only green. NOTE the two-hats split: the
  *language* is N; a **NilPy IDE or app built with it is an E app** (Track B
  file-ownership), never N — same P-vs-A distinction as everywhere.
  **What counts as an N bug — NilPy is UPWARD COMPATIBLE with CPython:** *if code
  works on CPython, it must work on NilPy.* One direction only. NilPy accepting
  something CPython **rejects** (a mutated tuple, a stricter-in-CPython form) is a
  **language feature, not a defect** — the same call the Pascal dialect makes for
  restrictions that were historic rather than necessary. So before filing "we are
  laxer than CPython", ask whether a program CPython *accepts and runs* can
  observe it; if not, it belongs in `devdocs/dev/nilpy-semantics-divergences.md`,
  not in a bug ticket. (Worked example on that page: a NilPy tuple being mutable
  is NOT a bug; `isinstance(t, list)` answering True IS, because ordinary
  working code branches on it.)
- **Track U — User (the decision lane).** Where human judgment lives. NOT a
  file-lane: owns no source, has no gate, builds nothing — it is the **escalation
  target**. The rule for every agent, and *especially* an autonomous/scheduled
  one: **escalate, don't guess.** When you hit a fork you can't settle from the
  code, the request, or a sensible default — a design choice, "is this intended vs
  a bug?", a spec ambiguity, a semantics/wording call — **file a Track U ticket
  (slug `decide-<topic>`: state the fork, the options, the trade-offs, your
  recommendation) and move on**; do not burn cycles guessing or silently pick a
  direction that may be wrong. The user works Track U to steer — resolving a
  `decide-*` unblocks the ranked chain behind it (prio propagates down dep edges).
  A U item that turns out to be plain work once decided is re-filed into the owning
  lane (U holds *open questions*, not work). The `decide-*` tickets already in the
  backlog ARE Track U. Full autonomy model — scheduled per-lane workers, gates,
  review cadence — in **`devdocs/dev/autonomy.md`**.
- **Track W — website (a real file-lane, in a SEPARATE repo).** The public site:
  the private `~/pxx-website` repo (app, `deploy/`, `secrets/`, blog), its
  deploy/secrets tooling and hosting. It earns a letter under the "don't invent
  letters" rule precisely because it passes that rule's own test — a genuinely
  new **place code lives**, the way Track T's watcher runs in its own clone. It
  is NOT `docs/**`: Track D writes the Markdown *in this repo* that the site
  publishes verbatim; W owns the machinery that publishes it. Rationale and the
  lane's gate: `feature-web-track-w-bootstrap`.
- **Track M — MSWindows (formal category, file-owned by A / B / T).** The
  Windows campaign as one visible lane: the PE/COFF writer and MS x64 ABI
  (**A**), the win32 widgetset and Tk-on-Windows compat in `lib/pcl` (**B**),
  the Wine test harness (**T**). Exactly S's shape and rules — a **work-tag, not
  a file-lane**: every M ticket ALSO carries its A/B/T file ownership for
  collision purposes and obeys **that** lane's gate. `*-windows-*` /
  `*-win32-*` / `*-wine-*` slugs auto-tag M. **M and not W**: W is the website
  lane above, and Windows is not a place code lives. The two claimed W
  simultaneously for months without anyone noticing, because Windows declared it
  in frontmatter and the website in prose, so neither side's grep saw the other
  (`meta-track-w-collision-windows-vs-website`). Declare a track in
  **frontmatter** — that is what the ranker reads.


## Parking a held change — an EDIT you can re-apply, never a copy of a shared file

Measured 2026-08-30 (frankS), and it is the one failure mode from that day's
ten-agent run that would have **destroyed another lane's work with no conflict and
no diagnostic**.

When you must hold a change — waiting for a pin, waiting for a sibling to land —
park it as something you **re-apply**: a patch (`git diff > x.patch`), a stash, or
a scripted set of anchored edits. **Never as a whole-file copy of a shared file.**

A file copy is a snapshot of the *entire file*, including every other lane's work
that was in it at copy time. Restoring it over a tree that has moved reverts all
of that — and git shows a **clean, well-formed commit**, because from git's point
of view nothing conflicted. frankS's copies of `defs.inc` and `cpreproc.inc` would
have reverted `CUnitOfPascalProgram` and 124 changed lines of `cpreproc.inc`.

**Do not rely on the build to catch it.** frankS's case surfaced as `undefined
variable (CUnitOfPascalProgram)` — but *only because the reverted code had a live
caller*. Clobber something self-contained — a new function not yet called, a test,
a helper — and it compiles clean, reaches a valid fixedpoint, and lands. The gate
caught this one by luck, not by coverage.

**When something does surface, separate "my copy is stale" from "master is
broken" in one command:** build with the **pinned** compiler against a **clean**
tree. If that works, the fault is yours. frankS nearly reported a broken master.

Sibling hazard, opposite blast radius: a **stale binary** (see CLAUDE.md's per-fix
loop, and `session-roster.md`). A stale binary corrupts *your own verdict*; a
stale file copy destroys *other people's work*.

Re-apply against current HEAD with **every anchor asserted**, so a moved anchor
fails loudly instead of applying somewhere plausible.
