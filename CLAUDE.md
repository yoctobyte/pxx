# frankonpiler — agent guide

PXX / pascal26: a self-hosting Pascal-dialect compiler (FPC-seeded), with its own
RTL, multiple backends (x86-64 default IR; i386 / aarch64 / arm32 / xtensa /
riscv cross targets), and a Nil-Python frontend. The authoritative source of
project state is `docs/progress/BOARD.md` (regenerate with `tools/progress.sh
board-md`).

## Four parallel agents — figure out which one you are

The user runs **multiple Claude agents at once** on this repo, split by track.
The letter is a stable ID; **always pair it with its name** (e.g. "Track C
(C frontend)") so the slot is never ambiguous — note C = the *C-language*
frontend, D = *documentation* (the letters were chosen so C matches the C
language). **At session start, infer your track from the request:**

- **Track A — compiler (Pascal).** codegen / IR / backends / a target, parser /
  lexer / ABI / ELF, bootstrap / self-host / `make stabilize`, compiler bugs,
  language features, `compiler/**`. Works on `master`.
- **Track B — libraries / demos.** `lib/rtl` · `lib/pcl`, `examples/**`, writing
  or fixing a library (JSON, hashing, `IntToStr`, `Copy`…), demo apps, `make
  lib-test` / `make demos`, tickets tagged "(library)". Works on `master`.
- **Track C — C frontend (cfront).** The C-language frontend
  (`compiler/clexer.inc`, `cparser.inc`, `cpreproc.inc`, C-exclusive C→IR
  lowering), `lib/crtl`, C tests. **Works on a branch in its own worktree**
  (`feat/cfront`, `../frankonpiler-cfront`) — never on `master` — because adding
  the C frontend changes the compiler binary (reseed) and must stay off A/B/D's
  ground until a stable slice merges.
- **Track D — documentation (user / website).** `docs/site/**` — the user-facing
  docs the website pulls straight from git and publishes (getting-started,
  language reference, tutorials, install, the public landing copy). Prose only:
  **never** touches `compiler/**` or `lib/**`. NOT the internal dev docs
  (`docs/dev/**`) or the agent board (`docs/progress/**`) — those belong to A/B.
  Works on `master`.

If genuinely ambiguous, **ask: "Track A (compiler), B (libraries/demos), C (C
frontend), or D (docs/website)?"** — don't guess; the tracks have opposite rules
about rebuilding the compiler and where they work.

Full protocol, including the stable-binary boundary, the lib-test/demos
discovery→ticket loop, and shared-checkout coordination, is in
**`docs/dev/parallel-tracks.md`**. Read it before starting your track.

### Track A in one line
Own `compiler/**` (shared internals: AST, IR, symtab, backends, ABI, ELF). Gate
= `make test` + self-host fixedpoint (byte-identical). When a feature B/C needs
lands: `make stabilize` (records a checkpoint, moves `latest`) then `make pin`
(blesses it, moves `pinned`), then commit `stable_linux_amd64/**`. `make
stabilize` alone does NOT move B's ground.

### Track B in one line
Build everything with `$(PXX_STABLE)` (= `stable_linux_amd64/default/pinned`);
never rebuild the compiler. `make lib-test` (green smoke) / `make demos`
(dashboard). Compiler/language gaps → file a ticket in `docs/progress/backlog`.

### Track C in one line
Own the C-frontend files; build the C compiler on the `feat/cfront` branch.
**Shared compiler internals stay A's** — a new AST node / IR op / symtab field /
backend change → **file a Track A ticket** (A implements + pins; C builds on the
pinned compiler). Never edit shared AST/IR/codegen unilaterally — that is the
rule that keeps A's self-host gate safe. Gate = C tests green + self-host
byte-identical + cross. Rebase on `master` periodically (C builds the compiler,
so it must absorb A's pins). **Merging `feat/cfront` → `master` is a Track A
event** (re-pin), not a quiet fast-forward.

### Track D in one line
Own `docs/site/**` (Markdown the website publishes verbatim from git). No build,
no compiler, no `lib/**`. Gate = docs stay internally consistent and examples
compile against `$(PXX_STABLE)` (never rebuild). A compiler/library gap found
while documenting → file a ticket in `docs/progress/backlog`, don't fix code.
Verify code snippets by compiling them; don't invent behaviour.

## Workflow norms (all tracks)
- A / B / D work directly on `master` (no worktrees/clones); **C works on
  `feat/cfront` in its own worktree**. Commit in small units.
- `git pull --rebase` before pushing; push promptly. Stay in your lane's files.
- **Push only your own lane.** Each track pushes the commits it made. During a
  sync, do **not** push, commit, or rebase another track's branch or in-flight
  work — not even a clean fast-forward of a sibling's commit. That track pushes
  its own.
- **Push freely when the tree is stable** — green where it matters (your lane's
  gate: A `make test` + self-host; B `make lib-test`/`demos`; C C-tests +
  self-host + cross; D snippets compile), no half-finished edit committed.
  History is reversible, so a stable push is always safe; you do NOT need to ask
  each time. The old "never push without ok" rule is retired. Still: don't push a
  known-broken or mid-refactor state, and don't push another agent's in-flight
  uncommitted work — only what you committed.
- Tickets live in
  `docs/progress/{urgent,working,unfinished,backlog,blocked,done,rejected}/`;
  regenerate `BOARD.md` after moving them. `working/` is a **live lock** — a
  ticket sits there only while an agent is actively on it. When work halts with
  the ticket incomplete (e.g. parked waiting on another fix), move it to
  `unfinished/`. A **Track B** ticket in `unfinished/` is fine to park; a **Track
  A** one is CRITICAL (a half-applied compiler change can break the stable-binary
  / self-host gate) and `tools/progress.sh check` fails until it is resolved or
  reverted.
