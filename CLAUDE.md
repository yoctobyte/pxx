# frankonpiler — agent guide

PXX / pascal26: a self-hosting Pascal-dialect compiler (FPC-seeded), with its own
RTL, multiple backends (x86-64 default IR; i386 / aarch64 / arm32 / xtensa /
riscv cross targets), and a Nil-Python frontend. The authoritative source of
project state is `docs/progress/BOARD.md` (regenerate with `tools/progress.sh
board-md`).

## Two parallel agents — figure out which one you are

The user runs **two Claude agents at once** on this same repo/branch, split by
track. **At session start, infer your track from the request:**

- **Track A — compiler.** codegen / IR / backends / a target, parser / lexer /
  ABI / ELF, bootstrap / self-host / `make stabilize`, compiler bugs, language
  features, `compiler/**`.
- **Track B — libraries / demos.** `lib/rtl` · `lib/pcl`, `examples/**`, writing
  or fixing a library (JSON, hashing, `IntToStr`, `Copy`…), demo apps, `make
  lib-test` / `make demos`, tickets tagged "(library)".

If genuinely ambiguous, **ask: "Track A (compiler) or B (libraries/demos)?"** —
don't guess; the tracks have opposite rules about rebuilding the compiler.

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

## Workflow norms (both tracks)
- Work directly on `master` (no worktrees/clones). Commit in small units.
- `git pull --rebase` before pushing; push promptly. Stay in your lane's files.
- **Push freely when the tree is stable** — green where it matters (your lane's
  gate: Track A `make test` + self-host; Track B `make lib-test`/`demos`), no
  half-finished edit committed. History is reversible, so a stable push is always
  safe; you do NOT need to ask each time. The old "never push without ok" rule is
  retired. Still: don't push a known-broken or mid-refactor state, and don't push
  another agent's in-flight uncommitted work — only what you committed.
- Tickets live in `docs/progress/{urgent,working,backlog,blocked,done,rejected}/`;
  regenerate `BOARD.md` after moving them.
