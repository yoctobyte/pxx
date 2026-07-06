# frankonpiler — agent guide

PXX / pascal26: a self-hosting Pascal-dialect compiler (FPC-seeded), with its own
RTL, multiple backends (x86-64 default IR; i386 / aarch64 / arm32 / xtensa /
riscv cross targets), and a Nil-Python frontend. The authoritative source of
project state is `devdocs/progress/BOARD.md` (regenerate with `tools/progress.sh
board-md`).

## Tracks — coordination lanes, not a taxonomy

The user runs **multiple Claude agents at once** on this repo. A track is a
**lane to keep concurrent agents from clobbering each other's files, plus the
gate each must stay green** — it is NOT an ontology of the codebase. So:

- **One agent often holds several tracks** (e.g. "you're A+B+C"). That's the
  normal case, not a failure — then you're free to touch all of them, you just
  respect every gate you span. The letters only matter *when* two agents run at
  once and must not fight over the same file.
- **Don't invent new letters.** No Track L for libraries, no "LC" for C
  libraries. The set below is deliberately small; resist splitting it finer.

Two axes cut the repo, and the tracks follow them:

1. **Accepted languages (frontends)** — what the compiler *parses*: **P** Pascal
   (the full dialect — classes, generics, RTL semantics, *far* past the subset
   self-host needs), **C**, **R** Rust, **Z** Zig. Each is a whole language with
   its own tests; each lowers to the shared IR.
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
  frontend, peer of C/Z, not "the compiler's impl language." *Physical catch:*
  Pascal was the seed, so its frontend still lives inside the SHARED `lexer.inc`
  / `parser.inc` (and Pascal-facing `defs.inc` / `symtab.inc`) rather than its
  own `plexer` / `pparser` the way C got carved out. So today P shares those
  files with A: same `master`, same self-host gate, same node/token-numbering
  discipline, and **P and A must not edit them concurrently** (combined-track
  note below). Anything below the frontend (IR ops, backends, ABI, ELF) is core
  A. The clean long-term shape is to split out `plexer`/`pparser` so P owns files
  like C/Z do. Works on `master`.
- **Track R — Rust frontend (rfront).** The Rust-language frontend and its
  Rust→IR lowering, `lib/rrtl` (as it lands), Rust tests. Live work in
  `devdocs/progress/working/feature-rust-*`. Same rule as C/Z: own your frontend
  files; shared-internals change → **file a Track A ticket**. Works on `master`.
- **Track Z — Zig frontend (zfront).** The Zig-language frontend, greenfield:
  future `compiler/zlexer.inc`, `zparser.inc`, Zig-exclusive Zig→IR lowering,
  `lib/zrtl`, Zig tests. **Works on `master`**, under the same pin boundary as C.
  Same rule as C: own your frontend files; a shared-internals change (new AST
  node / IR op / symtab field / backend / anything in `lexer.inc`, `parser.inc`,
  `ir*.inc`, `symtab.inc`, `defs.inc`, the backends) → **file a Track A ticket**,
  do not edit it under Track Z. Gate = Zig tests green + self-host byte-identical
  + cross. Land only green; destabilizing work behind a flag or incremental,
  never a long-lived branch.

If genuinely ambiguous, **ask: "Track A (core), B (libraries/demos), C (C
frontend), D (docs/website), P (Pascal frontend), R (Rust frontend), or Z (Zig
frontend)?"** — don't guess; the tracks have opposite rules about rebuilding the
compiler and where they work. (And remember one agent may legitimately hold
several at once.)

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
Full Pascal-language frontend (peer of C/Z), but its files aren't carved out yet
— it lives in the SHARED `lexer.inc` / `parser.inc` (Pascal paths). So same
`master`, same gate = `make test` + self-host fixedpoint (byte-identical), plus
cross where a target is touched, and **never edit those files concurrently with
A**. IR / backends / ABI / ELF are core A: a Pascal feature needing a new IR op /
AST node is an A change (self-resolve if you also hold A, else file + hand off).

### Track R in one line
Own the Rust-frontend files (`rfront` lexer/parser, Rust→IR lowering, `lib/rrtl`,
Rust tests) on `master`; live work under `devdocs/progress/working/feature-rust-*`.
**Shared compiler internals stay A's** — new AST node / IR op / symtab field /
backend → **file a Track A ticket**, don't edit under R. Gate = Rust tests green +
self-host byte-identical + cross. Land only green; destabilizing work behind a
flag or incrementally, never a long-lived branch.

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
- **Self-serve queue:** `tools/progress.sh next --track <X>` prints the single
  top ticket to grab (and why); `ready --track <X>` is the whole ranked queue.
  Ranking = one human `prio:` (0-100, frontmatter, unset=50) propagated down
  dependency edges — a blocker inherits the priority of what it unblocks, so you
  rate goals and the chain follows. Loop `next → claim <slug> <agent> → do →
  resolve <slug> <commit> → board-md`. origin/master is truth (pull --rebase,
  push green). Full model: `devdocs/progress/README.md`.
- Tickets live in
  `devdocs/progress/{urgent,working,unfinished,backlog,blocked,done,rejected}/`;
  regenerate `BOARD.md` after moving them. `working/` is a **live lock** — a
  ticket sits there only while an agent is actively on it. When work halts with
  the ticket incomplete (e.g. parked waiting on another fix), move it to
  `unfinished/`. A **Track B** ticket in `unfinished/` is fine to park; a **Track
  A** one is CRITICAL (a half-applied compiler change can break the stable-binary
  / self-host gate) and `tools/progress.sh check` fails until it is resolved or
  reverted.
