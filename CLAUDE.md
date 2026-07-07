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
- **Track T — testing infra (watcher + agentic test manager).** Owns
  `tools/testmgr.py`, `tools/twatch.py`, `devdocs/progress/tstate/**` and the
  report format. Face 1 = the standalone twatch daemon (any box, its own
  dedicated clone, publishes sparse per-SHA regression reports to `tstate/`
  ONLY — that's the watcher identity's whole write scope). Face 2 = an agent
  (supervised session or cron) that consumes tstate, files/updates regression
  tickets like any track agent, and maintains the Track T codebase itself.
  Once a watcher is live, dev tracks may gate pushes on `testmgr --tier
  quick` + self-host fixedpoint; the full matrix runs offloaded, so master
  MAY carry cross-target reds for hours — tstate is the truth, and a
  core-job red older than a day is a revert candidate. Gate for T's own
  tooling changes = `tools/testmgr.py --tier full` green.
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
**`devdocs/dev/parallel-tracks.md`**. Read it before starting your track. The
*why* behind the whole track split — Track A / the IR is the one gate and the one
multiplier, so push generality down into the core and keep frontends thin — is
the north-star note **`devdocs/dev/ir-as-substrate.md`**.

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

### Combined-track assignment (one agent, several tracks)
The user may put a single agent on **more than one track** — e.g. "you are Track
A *and* C". Then the tracks stay distinct (own files, own gates) and a shared-code
change is **still filed as a Track A ticket** for traceability — but the *same
agent may resolve its own ticket*, because the user has confirmed no other agent
holds Track A concurrently, so there is no coordination hazard. File → (normally
hand off) → here, file → self-resolve. Drop back to file-and-hand-off the moment
the agent is single-track again.

Not all combinations carry the same risk, and it's about **shared files, not
topics**:
- **Frontend + frontend** (C/P/R/Z pairs) is the low-risk combo — each owns a
  mostly-disjoint file set (`cparser` vs `zparser` vs the Rust files…), so their
  edits merge cleanly. The catch is **P**: the Pascal frontend still lives in the
  *shared* `lexer.inc`/`parser.inc`, so "P + anything" touches A's ground — treat
  the P edits under A's gate + no-concurrent-edit rule.
- **Anything + A** is the combo that needs the "no other agent holds A"
  confirmation, because A is where the shared files (`ir*.inc`, `symtab.inc`,
  `defs.inc`, backends, and the P-shared `lexer`/`parser`) actually live. Two
  agents editing one of those at once is the only real hazard the letters exist
  to prevent.

Even when the source would merge, keep the *default* to one lane (top of this
section) — combining is a deliberate call the user makes, not a convenience you
reach for, because the context cost lands on your reasoning, not on git.

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

### Track T in one line
Own the test infra: `tools/testmgr.py`, `tools/twatch.py`,
`devdocs/progress/tstate/**`. Face 1 (watcher daemon) writes ONLY `tstate/`;
face 2 (agent, supervised or cron) files regression tickets and OWNS the T
codebase: it is free to improve/refactor/optimize Track T sources (testmgr,
twatch, report format, tier composition) on its own initiative — no ticket or
approval needed, self-optimization is part of the job. Gate for T tooling
changes = `tools/testmgr.py --tier full` green — and test the tooling itself
with QUICK tiers + a scratch bare repo, never long runs.

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
  worktree is retired. Exception: Track T's watcher daemon runs in its own
  dedicated clone — it's infra, not a dev agent.)
- **Confirm native, offload the matrix.** After a change, ALWAYS confirm it
  works natively yourself: `tools/testmgr.py --tier quick` plus self-host
  fixedpoint for compiler changes (≈40s). The breadth — cross targets, corpus,
  regressions elsewhere — is Track T's job *when a watcher is up*. Check with
  `tools/twatch.py --status` (no network, no ping: reads `tstate/` vs git
  history; a commit older than the grace window that nobody tested = T down).
  Exit 0 → push after the native confirm; regressions come back asynchronously
  as tstate reports/tickets tied to your exact SHA. Exit 1 → T is down/absent:
  the old rules apply — run your lane's full gate (`tools/testmgr.py --tier
  full`, or `--tier limited` + the targets your change touches) before pushing
  anything risky.
- `git pull --rebase` before pushing; push promptly. Stay in your lane's files.
- **Push only your own lane.** Each track pushes the commits it made. During a
  sync, do **not** push, commit, or rebase another track's branch or in-flight
  work — not even a clean fast-forward of a sibling's commit. That track pushes
  its own.
- **Push OFTEN — pushing is the default, not a milestone.** Track T only sees
  what lands on origin/master, so unpushed work is untested work: commit each
  logical unit and push it after the native confirm (quick + self-host — see
  "confirm native, offload the matrix" above). When `twatch --status` says T
  is down, the bar rises to your lane's full gate for risky changes (A `make
  test` + self-host; B `make lib-test`/`demos`; C C-tests + self-host + cross;
  D snippets compile). You never need to ask before pushing. Still: don't push
  a known-broken or mid-refactor state, and don't push another agent's
  in-flight uncommitted work — only what you committed.
- **Self-serve queue:** `tools/progress.sh next --track <X>` prints the single
  top ticket to grab (and why); `ready --track <X>` is the whole ranked queue.
  Ranking = one human `prio:` (0-100, frontmatter, unset=50) propagated down
  dependency edges — a blocker inherits the priority of what it unblocks, so you
  rate goals and the chain follows. Loop `next → claim <slug> <agent> → do →
  resolve <slug> <commit> → board-md`. origin/master is truth (pull --rebase,
  push green). Full model: `devdocs/progress/README.md`.
- **Cold start — "continue on tickets" (no track named):** self-dispatch,
  auto-pick the global top.
  1. `git pull --rebase` (origin is truth).
  2. `tools/progress.sh next` — the single highest-effective-prio ready ticket,
     any track. (If the user *did* name a track, use `next --track <X>` instead.)
  3. **Sole-A guard:** if that ticket is Track A — or a Track P edit that touches
     the shared `lexer.inc`/`parser.inc` (i.e. it edits shared core/IR files) —
     confirm you are the *only* agent on Track A right now; ask the user if you
     can't tell. If you're not sole-A, skip it and take the top of a non-A track
     (`next --track C|B|R|D`). Any non-shared ticket: just claim it.
  4. `claim <slug> <agent-id>` → do it → land green (your lane's gate) →
     `resolve <slug> <commit>` → `board-md` → commit the move + push.
  5. Loop: `pull --rebase`, `next`, repeat. Stop when the queue is dry for your
     lane or the user says so.
- Tickets live in
  `devdocs/progress/{urgent,working,unfinished,backlog,blocked,done,rejected}/`;
  regenerate `BOARD.md` after moving them. `working/` is a **live lock** — a
  ticket sits there only while an agent is actively on it. When work halts with
  the ticket incomplete (e.g. parked waiting on another fix), move it to
  `unfinished/`. A **Track B** ticket in `unfinished/` is fine to park; a **Track
  A** one is CRITICAL (a half-applied compiler change can break the stable-binary
  / self-host gate) and `tools/progress.sh check` fails until it is resolved or
  reverted.
