# frankonpiler — agent guide

PXX / pascal26: a self-hosting Pascal-dialect compiler (FPC-seeded), with its own
RTL, multiple backends (x86-64 default IR; i386 / aarch64 / arm32 / xtensa /
riscv cross targets), and a Nil-Python frontend. The authoritative source of
project state is `docs/progress/BOARD.md` (regenerate with `tools/progress.sh
board-md`).

## Four parallel agents — figure out which one you are

The user runs **multiple Claude agents at once** on this same repo/branch, split
by track. **At session start, infer your track from the request:**

- **Track A — compiler core.** codegen / IR / backends / a target, parser /
  lexer / ABI / ELF, bootstrap / self-host / `make stabilize`, compiler bugs,
  Pascal language features, `compiler/**` (the Pascal frontend, shared IR, and
  backends).
- **Track B — libraries / demos.** `lib/rtl` · `lib/pcl`, `examples/**`, writing
  or fixing a library (JSON, hashing, `IntToStr`, `Copy`…), demo apps, `make
  lib-test` / `make demos`, tickets tagged "(library)".
- **Track C — C frontend.** Compiling **C source**: `compiler/clexer.inc`,
  `compiler/cparser.inc`, `compiler/cpreproc.inc`, the `test/*.c` fixtures, and
  the `c-interop-devtest` suite. Worked on the isolated `feat/cfront` branch /
  worktree. North star: compile real portable C (tiny-regex → lua → sqlite,
  ticket `feature-c-desktop-lua-sqlite-path`). C-body lowering goes through the
  **shared IR**, so it edits the compiler binary → same self-host / reseed
  discipline as Track A.
- **Track D — documentation (user / website).** `docs/site/**` — the user-facing
  docs the website pulls straight from git and publishes (getting-started,
  language reference, tutorials, install, the public landing copy). Prose only:
  **never** touches `compiler/**` or `lib/**`. NOT the internal dev docs
  (`docs/dev/**`) or the agent board (`docs/progress/**`) — those belong to A/C.

If genuinely ambiguous, **ask: "Track A (compiler core), B (libraries/demos), C
(C frontend), or D (docs/website)?"** — don't guess; A and C edit the compiler
binary (self-host gate), B never rebuilds it, and D must stay out of code
entirely.

Full protocol, including the stable-binary boundary, the lib-test/demos
discovery→ticket loop, and shared-checkout coordination, is in
**`docs/dev/parallel-tracks.md`**. Read it before starting either track.

### Track A in one line
Own `compiler/**`. Gate = `make test` + self-host fixedpoint (byte-identical).
When a feature B needs lands: `make stabilize` (records a checkpoint, moves
`latest`) then `make pin` (blesses it for B, moves `pinned`), then commit
`stable_linux_amd64/**`. `make stabilize` alone does NOT move B's ground.

### Track B in one line
Build everything with `$(PXX_STABLE)` (= `stable_linux_amd64/default/pinned`);
never rebuild the compiler. `make lib-test` (green smoke) / `make demos`
(dashboard). Compiler/language gaps → file a ticket in `docs/progress/backlog`.

### Track C in one line (C frontend)
Own the C-source path: `compiler/clexer.inc` · `compiler/cparser.inc` ·
`compiler/cpreproc.inc` + `test/*.c` fixtures + the `c-interop-devtest` suite.
Worked on the `feat/cfront` branch/worktree. Gate = `make test` + self-host
fixedpoint (byte-identical) — C-body lowering rides the **shared IR**, so it
touches the compiler binary exactly like Track A (a half-applied change is
CRITICAL). Keep body lowering in shared IR, not per-target codegen (cross
landmines). Oracle = gcc/tcc stdout-equality. Roadmap =
`feature-c-desktop-lua-sqlite-path`; shared-IR touch-points are tracked in
`track-a-c-frontend-shared-ir-touchpoints` for A to reconcile.

### Track D in one line (docs)
Own `docs/site/**` (Markdown the website publishes verbatim from git). No build,
no compiler, no `lib/**`. Gate = docs stay internally consistent and examples
compile against `$(PXX_STABLE)` (never rebuild). A compiler/library gap found
while documenting → file a ticket in `docs/progress/backlog`, don't fix code.
Verify code snippets by compiling them; don't invent behaviour.

## Workflow norms (all tracks)
- Work directly on `master` (no worktrees/clones). Commit in small units.
- `git pull --rebase` before pushing; push promptly. Stay in your lane's files.
- **Push freely when the tree is stable** — green where it matters (your lane's
  gate: Track A `make test` + self-host; Track B `make lib-test`/`demos`), no
  half-finished edit committed. History is reversible, so a stable push is always
  safe; you do NOT need to ask each time. The old "never push without ok" rule is
  retired. Still: don't push a known-broken or mid-refactor state, and don't push
  another agent's in-flight uncommitted work — only what you committed.
- Tickets live in
  `docs/progress/{urgent,working,unfinished,backlog,blocked,done,rejected}/`;
  regenerate `BOARD.md` after moving them. `working/` is a **live lock** — a
  ticket sits there only while an agent is actively on it. When work halts with
  the ticket incomplete (e.g. parked waiting on another fix), move it to
  `unfinished/`. A **Track B** or **Track D** ticket in `unfinished/` is fine to
  park; a **Track A** or **Track C** one is CRITICAL (both edit the compiler
  binary, so a half-applied change can break the stable-binary / self-host gate)
  and `tools/progress.sh check` fails until it is resolved or reverted.
