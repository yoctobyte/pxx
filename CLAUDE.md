# pxx — agent guide

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
- **Two axes: lanes vs tags.** The letters mix two kinds of thing, and that's
  fine once you see it. **File-lanes** (exclusive, collision-avoidance): **A**
  core, **B** libs/demos, **C/N/P/R/Z** frontends — these answer "who owns this
  file when two agents run at once." **Work-tags** (human grouping, compose
  freely, each *inherits* a file-lane): **O** optimization (owned by A), **E**
  examples/apps (owned by B), **T** testing, **D** docs, **X** experimental. A
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
- **Track Z — Zig frontend (zfront).** The Zig-language frontend, greenfield:
  future `compiler/zlexer.inc`, `zparser.inc`, Zig-exclusive Zig→IR lowering,
  `lib/zrtl`, Zig tests. **Works on `master`**, under the same pin boundary as C.
  Same rule as C: own your frontend files; a shared-internals change (new AST
  node / IR op / symtab field / backend / anything in `lexer.inc`, `parser.inc`,
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
  in `lexer.inc`, `parser.inc`, `ir*.inc`, `symtab.inc`, `defs.inc`, the backends)
  → **file a Track A ticket**, do not edit it under N. Gate = `test-nilpy` green +
  self-host byte-identical + cross. Land only green. NOTE the two-hats split: the
  *language* is N; a **NilPy IDE or app built with it is an E app** (Track B
  file-ownership), never N — same P-vs-A distinction as everywhere.
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

If genuinely ambiguous, **ask: "Track A (core), B (libraries/demos), C (C
frontend), D (docs/website), N (Nil-Python frontend), P (Pascal frontend), R (Rust
frontend), or Z (Zig frontend)?"** — don't guess; the tracks have opposite rules
about rebuilding the compiler and where they work. (And remember one agent may legitimately hold
several at once.) And whenever the fork is *what to build/decide* rather than
*which lane owns it*, that's **Track U** — file `decide-*`, don't guess.

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
- **Frontend + frontend** (C/N/P/R/Z pairs) is the low-risk combo — each owns a
  mostly-disjoint file set (`cparser` vs `pyparser` vs `zparser` vs the Rust files…),
  so their edits merge cleanly. So **A+N, B+N, N+C**, etc. are all fine — N owns
  `pylexer`/`pyparser`, disjoint from every other lane. The catch is **P**: the
  Pascal frontend still lives in the *shared* `lexer.inc`/`parser.inc`, so "P +
  anything" touches A's ground — treat the P edits under A's gate + no-concurrent-edit
  rule. (N does NOT have this catch — it's carved out like C/Z.) For automated /
  scheduled workers the overlap rules may need tuning, but a single supervised
  agent holding e.g. A+N is exactly the intended combined-track case.
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

### Track E in one line
Examples & apps (demos, games, GUIs, IDEs, the portable-userland/shell showcase)
= **file-owned by Track B**. Build with `$(PXX_STABLE)`, never rebuild the
compiler; gate = `make lib-test`/`demos` + the app runs. A compiler/frontend gap
an app hits → file it under the owning lane (A / the frontend), don't fix it under E.

### Track O in one line
Optimization lane = **implicitly Track A**. Codegen/runtime speed (register
allocation, `-O` passes, heap allocator). Edits A's shared files (`ir*.inc`,
`symtab.inc`, backends, `compiler/builtin/**`), so file it as a Track A ticket
(O is the visible grouping) and obey A's gate: `make test` + self-host
byte-identical (+ cross where a backend/runtime is touched). New passes land
behind `-O3`, promote to `-O2` per-pass only after the full gate; `-O2` is the
proven default and the stable fallback. Land only green.

### Track T in one line
Own the tools & test infra: `tools/testmgr.py`, `tools/twatch.py`,
`devdocs/progress/tstate/**`, and the fuzzers (`tools/fuzz.sh`,
`tools/pasmith*.py`, Csmith runs). Face 1 (watcher daemon) writes ONLY
`tstate/`; face 2 (agent, supervised or cron) files regression tickets, fuzzes
in spare cycles, and OWNS the T codebase: it is free to improve/refactor/
optimize Track T sources (testmgr, twatch, fuzzers, report format, tier
composition) on its own initiative — no ticket or approval needed,
self-optimization is part of the job. Gate for T tooling changes =
`tools/testmgr.py --tier full` green — and test the tooling itself with QUICK
tiers + a scratch bare repo, never long runs. Track T pushes CODE too (its own
tooling), not just tstate — those commits belong to lane T and follow the
push-your-own-lane rule: T touches `tools/testmgr.py` / `tools/twatch*` /
`tools/fuzz.sh` / `tools/pasmith*` / `tstate/**` and nothing else. **T owns the
tool, never the bug**: a compiler or test-target gap it hits (including a fuzz
divergence) → ticket for the owning track (IR/codegen → A, dialect → P,
RTL → B), never a fix under T.

### Track Z in one line
Own the Zig-frontend files (`zlexer` / `zparser`, Zig→IR lowering, `lib/zrtl`,
Zig tests) on `master`. **Shared compiler internals stay A's** — a new AST node /
IR op / symtab field / backend change → **file a Track A ticket**, don't edit it
under Z (keeps A's self-host gate safe, stops node-number / token collisions).
Gate = Zig tests green + self-host byte-identical + cross. Land only green; big
destabilizing work behind a flag or incrementally, never a long-lived branch.

### Track N in one line
Own the Nil-Python frontend files (`pylexer.inc` / `pyparser.inc`, Python→IR
lowering, `.npy` tests) on `master`. Mainline + gated (peer of C, not X). **Shared
compiler internals stay A's** — new AST node / IR op / symtab field / backend
change → **file a Track A ticket**, don't edit under N. Gate = `test-nilpy` green +
self-host byte-identical + cross. Land only green. The language is N; an IDE/app
built with NilPy is an E app (Track B), not N.

### Track U in one line
The decision lane — human judgment, no files, no gate, no build. **Escalate,
don't guess:** hit a design/intent/semantics fork you can't settle from code,
request, or a sane default → file `decide-<topic>` (fork + options + trade-offs +
your recommendation) and move to the next queue item. The user resolves `decide-*`
to steer; one answer unblocks the ranked chain behind it. A U item that's plain
work once decided → re-file into the owning lane. See `devdocs/dev/autonomy.md`.

## Claims discipline — TWO different "byte-identical", never conflate them
Internal shorthand blurs these; **public-facing copy must not**. A compiler engineer
will catch it in seconds and the correction costs more than the claim ever gained.

| claim | what is identical | to what | kind |
| --- | --- | --- | --- |
| **self-host fixedpoint** | the **binary** | our own previous output | true binary reproducibility |
| **zlib / C corpora vs the gcc oracle** | the **program's OUTPUT** (e.g. zlib's compressed stream) | the output of a gcc-**built** zlib | *behavioral* parity |

We do **NOT** emit the same machine code as gcc and must never imply it. Say
"zlib built with pxx produces compressed output byte-identical to a gcc-built
zlib's", never "zlib byte-identical to gcc". Both claims are strong; they are
strong for different reasons.

Applies to: `docs/**`, the website, release notes, README, any promo/launch copy.
Write public claims **uncompressed** — the qualifying words ("output", "oracle",
"built with") carry the entire distinction, and terse styles drop them first.

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
