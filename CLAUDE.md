# frankonpiler — agent guide

PXX / pascal26: a self-hosting Pascal-dialect compiler (FPC-seeded), with its own
RTL, multiple backends (x86-64 default IR; i386 / aarch64 / arm32 / xtensa /
riscv cross targets), and a Nil-Python frontend. The authoritative source of
project state is `devdocs/progress/BOARD.md` (regenerate with `tools/progress.sh
board-md`).

## Six parallel agents — figure out which one you are

The user runs **multiple Claude agents at once** on this repo, split by track.
The letter is a stable ID; **always pair it with its name** (e.g. "Track C
(C frontend)") so the slot is never ambiguous — the letters are mnemonic:
C = the *C-language* frontend, D = *documentation*, P = the *Pascal*-language
frontend, Z = the *Zig* frontend. **At session start, infer your track from the
request:**

- **Track A — compiler (Pascal).** codegen / IR / backends / a target, parser /
  lexer / ABI / ELF, bootstrap / self-host / `make stabilize`, compiler bugs,
  language features, `compiler/**`. Works on `master`.
- **Track B — libraries / demos.** `lib/rtl` · `lib/pcl`, `examples/**`, writing
  or fixing a library (JSON, hashing, `IntToStr`, `Copy`…), demo apps, `make
  lib-test` / `make demos`, tickets tagged "(library)". Works on `master`.
- **Track C — C frontend (cfront).** The C-language frontend
  (`compiler/clexer.inc`, `cparser.inc`, `cpreproc.inc`, C-exclusive C→IR
  lowering), `lib/crtl`, C tests. **Works on `master`** (as of v80, when the C
  frontend merged in — the old `feat/cfront` worktree is retired). The branch
  existed only while C was destabilizing; now C *is* part of the compiler, so it
  lives on `master` like everyone else, protected by the same pin boundary (B/D
  build on `pinned`, not HEAD).
- **Track D — documentation (user / website).** `docs/**` — the user-facing
  docs the website pulls straight from git and publishes (getting-started,
  language reference, tutorials, install, the public landing copy). Prose only:
  **never** touches `compiler/**` or `lib/**`. NOT the internal dev docs
  (`devdocs/dev/**`) or the agent board (`devdocs/progress/**`) — those belong to A/B.
  Works on `master`.
- **Track P — Pascal-language frontend.** The Pascal *dialect* itself: Pascal
  syntax / semantics / new language features and their frontend bugs, living in
  the Pascal paths of `lexer.inc` / `parser.inc` (plus Pascal-facing `defs.inc`
  / `symtab.inc` entries). **These are the SHARED front-of-compiler files A also
  owns** — Pascal, being the seed language, has no separate frontend includes
  the way C has `cparser.inc` et al. So P is *scoped Track A*: same `master`,
  same self-host gate, same node/token-numbering discipline. Any change below
  the frontend (IR ops, backends, ABI, ELF) is still core A work. P and A must
  not run concurrently on the same shared files — coordinate exactly like the
  combined-track note below. Works on `master`.
- **Track Z — Zig frontend (zfront).** The Zig-language frontend, greenfield:
  future `compiler/zlexer.inc`, `zparser.inc`, Zig-exclusive Zig→IR lowering,
  `lib/zrtl`, Zig tests. **Works on `master`**, under the same pin boundary as C.
  Same rule as C: own your frontend files; a shared-internals change (new AST
  node / IR op / symtab field / backend / anything in `lexer.inc`, `parser.inc`,
  `ir*.inc`, `symtab.inc`, `defs.inc`, the backends) → **file a Track A ticket**,
  do not edit it under Track Z. Gate = Zig tests green + self-host byte-identical
  + cross. Land only green; destabilizing work behind a flag or incremental,
  never a long-lived branch.

If genuinely ambiguous, **ask: "Track A (compiler), B (libraries/demos), C (C
frontend), D (docs/website), P (Pascal frontend), or Z (Zig frontend)?"** —
don't guess; the tracks have opposite rules about rebuilding the compiler and
where they work.

Full protocol, including the stable-binary boundary, the lib-test/demos
discovery→ticket loop, and shared-checkout coordination, is in
**`devdocs/dev/parallel-tracks.md`**. Read it before starting your track.

### Track A in one line
Own `compiler/**` (shared internals: AST, IR, symtab, backends, ABI, ELF). Gate
= `make test` + self-host fixedpoint (byte-identical). When a feature B/C needs
lands: `make stabilize` (records a checkpoint, moves `latest`) then `make pin`
(blesses it, moves `pinned`), then commit `stable_linux_amd64/**`. `make
stabilize` alone does NOT move B's ground.

### Track B in one line
Build everything with `$(PXX_STABLE)` (= `stable_linux_amd64/default/pinned`);
never rebuild the compiler. `make lib-test` (green smoke) / `make demos`
(dashboard). Compiler/language gaps → file a ticket in `devdocs/progress/backlog`.

### Track C in one line
Own the C-frontend files (`clexer`/`cparser`/`cpreproc`, C→IR lowering,
`lib/crtl`, C tests) on `master`. **Shared compiler internals stay A's** — a new
AST node / IR op / symtab field / backend change (anything in `lexer.inc`,
`parser.inc`, `ir*.inc`, `symtab.inc`, `defs.inc`, the backends) → **file a Track
A ticket**, do not edit it under Track C. That rule keeps A's self-host gate safe
and is what stops AST-node-number / token collisions. Gate = C tests green +
self-host byte-identical + cross. Land only green; big destabilizing work goes in
behind a flag or incrementally, never a long-lived branch.

### Combined-track assignment (one agent, two tracks)
The user may put a single agent on **two tracks at once** — e.g. "you are Track A
*and* C". Then the tracks stay distinct (own files, own gates) and a shared-code
change is **still filed as a Track A ticket** for traceability — but the *same
agent may resolve its own ticket*, because the user has confirmed no other agent
holds Track A concurrently, so there is no coordination hazard. File → (normally
hand off) → here, file → self-resolve. Drop back to file-and-hand-off the moment
the agent is single-track again.

### Track D in one line
Own `docs/**` (Markdown the website publishes verbatim from git). No build,
no compiler, no `lib/**`. Gate = docs stay internally consistent and examples
compile against `$(PXX_STABLE)` (never rebuild). A compiler/library gap found
while documenting → file a ticket in `devdocs/progress/backlog`, don't fix code.
Verify code snippets by compiling them; don't invent behaviour.

### Track P in one line
Own the Pascal-language surface in the SHARED `lexer.inc` / `parser.inc` (Pascal
paths) — scoped Track A, so same `master`, same gate = `make test` + self-host
fixedpoint (byte-identical), plus cross where a target is touched. IR / backends
/ ABI / ELF are core A. Because the files are shared with A, never run P and A on
them at once; on a Pascal feature that needs a new IR op / AST node, that part is
an A change (self-resolve if you also hold A, else file + hand off).

### Track Z in one line
Own the Zig-frontend files (`zlexer` / `zparser`, Zig→IR lowering, `lib/zrtl`,
Zig tests) on `master`. **Shared compiler internals stay A's** — a new AST node /
IR op / symtab field / backend change → **file a Track A ticket**, don't edit it
under Z (keeps A's self-host gate safe, stops node-number / token collisions).
Gate = Zig tests green + self-host byte-identical + cross. Land only green; big
destabilizing work behind a flag or incrementally, never a long-lived branch.

## Workflow norms (all tracks)
- **All tracks work directly on `master`** (no worktrees/clones). Commit in small
  units. (Historic: C used a `feat/cfront` worktree until it merged at v80; that
  worktree is retired.)
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
  `devdocs/progress/{urgent,working,unfinished,backlog,blocked,done,rejected}/`;
  regenerate `BOARD.md` after moving them. `working/` is a **live lock** — a
  ticket sits there only while an agent is actively on it. When work halts with
  the ticket incomplete (e.g. parked waiting on another fix), move it to
  `unfinished/`. A **Track B** ticket in `unfinished/` is fine to park; a **Track
  A** one is CRITICAL (a half-applied compiler change can break the stable-binary
  / self-host gate) and `tools/progress.sh check` fails until it is resolved or
  reverted.
