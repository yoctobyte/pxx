---
summary: "pasmith — Csmith-style random Object Pascal generator, FPC as differential oracle"
type: feature
prio: 70
---

# pasmith — random well-defined Object Pascal generator, differentially tested against FPC

- **Type:** feature (Track T — tools & testing)
- **Status:** backlog
- **Track:** T (owns the tool). Findings file into the owning lane: IR/codegen → A,
  dialect/frontend → P, ansistring/RTL → B. **T never fixes the compiler.**
- **Owner:** —
- **Related:** [[feature-ir-fuzzer]] (done — `tools/fuzz.sh`, the mutation half),
  [[feature-fuzzer-idle-scheduling]] (the "fuzz when idle" trigger — pasmith is a
  second producer for that same scheduler), [[feature-track-t-agent]] (the T agent
  that would run this in spare cycles and triage findings).
- **Opened:** 2026-07-13, from the Csmith session — Csmith drew blood on the C
  frontend; the question was whether an equivalent exists for FPC-dialect Pascal.
  It does not (surveyed: Csmith/YARPGen C, rustsmith, fuzz-d, Java*Fuzzer,
  GraphicsFuzz, sqlsmith — nothing for Pascal; the ANTLR `grammars-v4` Pascal/Delphi
  grammars are grammar-only and don't reach codegen, see Non-goals).

## Motivation — the blind spot `fuzz.sh` cannot see

`tools/fuzz.sh` (v1, [[feature-ir-fuzzer]]) mutates the existing `test/test_cross_*.pas`
corpus and uses a **cross-target differential** oracle: compile for x86-64 / i386 /
aarch64 / arm32 / riscv32, run each, diff stdout. That oracle has a structural blind
spot:

> **A bug in shared IR lowering produces the same wrong answer on every target.
> All five agree. The divergence is invisible.**

Cross-target differencing can only ever catch *backend-divergent* bugs. It cannot
catch a uniformly-wrong lowering — and that is precisely the class the Csmith
experience says dominates ("edge cases with assumptions", found in IR, not in the
lexer/parser). `fuzz.sh`'s 204-trial / 0-divergence clean run is consistent with the
bugs living exactly where its oracle is blind.

**An external reference implementation removes the blind spot entirely.** For Pascal
we have a free, mature, independent one: **FPC**. Same source, two compilers, diff
the output. This is the missing half of the fuzzing story, not a nicer `fuzz.sh`.

Second gap, orthogonal to the oracle: mutation-of-corpus can only reach shapes near
programs we already wrote. A *generative* smith reaches shapes nobody would write —
which is where "assumption" bugs hide by definition.

## Why this is tractable (and cheaper than Csmith was)

Csmith's hard 80% is **avoiding UB** — strict aliasing, signed overflow, sequence
points, uninitialized reads, integer-promotion rules. Every one of those is a way for
a generated program to be *legitimately* allowed to differ between compilers, making
the divergence a false positive. Pascal deletes most of that surface: no aliasing
rules to violate, evaluation order effectively fixed, overflow either defined or
trapped (`{$Q+}`/`{$R+}`), no integer-promotion swamp. The UB-avoidance work that
made Csmith a research project is, in Pascal, a short list.

What Pascal adds that C has no analogue for — and therefore the highest-yield target
here: **ansistring is a refcounted, copy-on-write, RTL-managed type with lifetime
rules.** Deeply nested ansistring temporaries across branches, exceptions, and
`try/finally` is where I'd expect the corpse. The C frontend structurally cannot
reach it; only a Pascal-shaped generator can.

## Design

### Generator: typed AST walk, NOT a grammar walk
This is the load-bearing decision. Csmith is **not** a grammar fuzzer — it's a typed
AST generator carrying a live symbol table, emitting only well-typed, in-scope,
UB-free code, so every program is runnable and every divergence is a real bug. A
grammar-directed generator (Grammarinator + a `.g4`) produces syntactically valid,
semantically dead programs — undeclared identifiers, type mismatches — which exercise
the parser and its error paths and **nothing below**. Since the bugs we're hunting are
below, a grammar fuzzer is the wrong instrument. Build the tree, don't parse it; the
grammar then comes free.

### Csmith invariants to steal verbatim
1. **UB-free by construction** — not "usually", by construction. Non-negotiable: a
   generator that can emit UB makes every divergence suspect and the tool dies of
   false positives. (`fuzz.sh` already learned the false-positive lesson the hard
   way — its first "8 divergences" were all seed-selection artifacts.)
2. **Single checksum output** — hash all live variables at exit, print ONE number.
   Not printed intermediate state. Makes diffing trivial and shrinking robust.
3. **Seeded, reproducible** — `pasmith --seed N` regenerates byte-for-byte; the seed
   goes in the generated file's header comment.
4. **Every program terminates** — bounded loops only, never `while` on a generated
   condition. Non-optional: `fuzz.sh` hung on its first run because a mutation turned
   a terminating loop infinite. Keep the `timeout` belt anyway.

### Oracles — plural, ranked, all free
1. **FPC** (primary — the one that removes the blind spot). `fpc -O2` and `fpc -O0`.
2. **pxx cross-target** (the `fuzz.sh` oracle, reused): 5 targets under QEMU via
   `tools/run_target.sh`.
3. **pxx self-differential**: `-O0` vs `-O2` vs `-O3`. Needs no FPC at all, and is
   free Track O coverage (new `-O3` passes are exactly the kind of thing this catches).

Run all of them, **majority vote**. A lone dissenter is the bug. This makes triage
mechanical instead of a judgment call.

### Triage rule — ordered suspicion, NOT dismissal
The prior favours "pasmith emitted something it shouldn't have", so that's where you
*look first*. It is an ordering of investigation, **not a verdict** — see the
selection-effect note below, which is the whole reason this section exists.

| observation | investigate in this order |
| --- | --- |
| FPC **rejects** the program (compile error) | **(a)** pasmith emitted invalid code — its contract is valid, well-typed `{$mode objfpc}` only; **(b)** we're relying on a dialect corner where pxx and FPC legitimately differ (→ a `compat-pascal-*` finding, not a bug in either); **(c)** FPC wrongly rejects valid code — a real FPC bug class, rarer but it exists. |
| FPC compiles; pxx and FPC outputs differ | **(a)** pasmith emitted implementation-defined / UB code — audit the generator's UB-avoidance FIRST, it's the cheapest check and the most common cause; **(b)** a pxx bug; **(c)** an FPC bug. |
| pxx targets disagree with each other | Backend/codegen bug (Track A) — same as `fuzz.sh` today. FPC not involved. |
| pxx `-O0` vs `-O2`/`-O3` disagree | Optimizer bug (Track A / Track O lane). FPC not involved. |

**Do NOT auto-dismiss an FPC failure (user, 2026-07-13).** The tempting shortcut —
"FPC is battle-tested, therefore it's us, close the case" — is wrong, and wrong for a
structural reason, not a charitable one:

> That "FPC is ~98% right" prior is a base rate over **all Pascal programs humans have
> ever written**. A fuzzer does not sample from that distribution. It deliberately
> samples the tail nobody has written before — which is *precisely* the region where
> FPC's own test suite is thinnest. Conditional on "we hit a shape no human wrote",
> P(FPC bug) is far higher than FPC's base bug rate. This is not hypothetical: Csmith
> found real bugs in GCC and LLVM, which are hammered orders of magnitude harder than
> FPC is.

So the base rate tells you **where to look first**; it does not tell you where to
stop. Every FPC failure gets **judgement**, not reflex: read the generated code, read
the FPC docs / language spec for the construct, check the FPC bugtracker, diff FPC
versions if available. Concretely, an FPC failure is only closed as "our bug" once you
can *point at the specific line* pasmith emitted that it shouldn't have — "FPC is
probably right" is not a resolution.

An FPC bug is a legitimate, valuable outcome of this tool and should be reported
upstream when found. It still has to be **earned**: shrink it first. Rule of thumb —
if the minimized reproducer isn't small and clean enough that you'd be comfortable
posting it to the FPC bugtracker, it isn't an FPC bug *yet*; it's an unfinished
investigation.

Corollary — this is what the extra oracles are *for*. FPC `-O0` vs FPC `-O2`
disagreeing on the same program is an FPC bug with no judgement call needed at all:
FPC contradicts itself, pxx isn't even in the room. Run it; it's free.

### Feature ladder — ship v1 narrow, widen on evidence
Each rung is independently useful; do not build them all before running.

- **v1 — scalar core.** Integer types (all widths, signed/unsigned), boolean, char.
  Arithmetic/bitwise/comparison, `if`/`case`, bounded `for`, nested blocks, local
  vars, procedures/functions with value + `var` + `const` params. Checksum at exit.
  This alone is enough to differential-test against FPC and is the smallest thing
  that can find a real bug.
- **v2 — Pascal-shaped types.** `record` (incl. packed, nested), static arrays, sets,
  enums, subranges, pointers. Sets and subranges are dialect surface C has nothing
  like.
- **v3 — the high-yield rung: managed types.** **ansistring** (concat, `Copy`,
  indexing, passing by value/`const`/`var`, as record fields, as function results),
  dynamic arrays, `try/finally`, exceptions. Refcount/COW/lifetime interactions —
  the reason a Pascal smith exists at all rather than just running Csmith.
- **v4 — objects.** Classes, inheritance, virtual dispatch, constructors/destructors.
- **v5 — generics.** If v1-v4 haven't already saturated the bug supply.

### Shrinking
On any divergence, delta-debug the generated file (delete/simplify statements while
the divergence persists) before filing. Non-optional: generated programs are large and
unreadable, and an unshrunk reproducer is a ticket nobody picks up. `fuzz.sh` already
has a minimizer — check whether it can be shared rather than rewritten.

### Where it lives
`tools/pasmith.py` (+ a `tools/pasmith_run.sh` driver, or fold the driver into
`tools/fuzz.sh` as a second generation mode — decide at pickup). Track T file
ownership, alongside `testmgr.py` / `twatch.py` / `fuzz.sh`.

## Track T charter amendment (implied by this ticket)
Track T's current CLAUDE.md scope is regression infra (`testmgr.py`, `twatch.py`,
`tstate/**`). This ticket reads T as **"Tools and Testing"** (user, 2026-07-13):
fuzzing tooling is a *tool used for testing*, so it belongs to T even though it is not
regression testing. Consequence: `tools/fuzz.sh` — filed and landed under **Track A**
via [[feature-ir-fuzzer]] — moves to **Track T** file ownership, joining pasmith. This
also gives the idle-fuzzing story its natural home: the Track T agent
([[feature-track-t-agent]]) fuzzes in spare cycles and triages findings into the
owning lanes, which is exactly the flow it already runs for tstate NEW-REDs.
CLAUDE.md's Track T section needs updating to say so — otherwise the next agent
re-derives the old, narrower boundary. (Applies to Csmith runs too: same tool-owns/
findings-file-elsewhere split.)

## Explicit non-goals
- **Not a grammar fuzzer.** No ANTLR `.g4`, no Grammarinator. Grammar-directed
  generation produces semantically dead programs that never reach IR — the wrong
  instrument for these bugs (see Design). Recorded here because it's the obvious
  first idea and it is wrong.
- **Not a CI gate.** Never blocks a commit or push. Out-of-band, time-boxed,
  opportunistic — same contract as `fuzz.sh`.
- **Not auto-filing tickets.** Findings land in a low-noise staging spot; a human or
  the T agent shrinks and triages before a real `bug-*.md` exists. (Same rule
  [[feature-fuzzer-idle-scheduling]] already sets.)
- **Not replacing `fuzz.sh`.** Complementary oracle (external reference vs
  cross-target self-consistency) and complementary generation (generative vs
  mutation-of-corpus). Both run.
- **Not other frontends.** C already has Csmith; Rust has rustsmith; Zig/Nil-Python
  are out of scope here. This is the Pascal-shaped hole.
- **Not chasing full dialect coverage.** Ship v1, run it, widen only where evidence
  says to.

## Acceptance
`pasmith --seed N` deterministically emits a UB-free, terminating, checksum-printing
Object Pascal program that **FPC compiles without error** (that's the contract, and
the first thing to prove). A driver compiles each generated program with pxx and FPC,
runs both, diffs the checksum, and shrinks on divergence. One real bounded run
completed and logged here — clean or not. A clean run is a valid result (same
inverted-success-criteria as [[feature-ir-fuzzer]]); a divergence becomes a shrunk
reproducer + a ticket in the owning lane + a permanent `test/test_*.pas` regression
test.

## Log
- 2026-07-13 — **shrinker removed; OOP + ansistring rungs landed** (commits 9e0cf382,
  07f4b35f). Two corrections to this ticket's own design, both from the user:

  **(1) No shrinker. Reduction was cargo-culted from Csmith without its premise.**
  Csmith shrinks because its reproducers go to *strangers* who won't read 40KB. Ours
  go to an agent in this repo, and the program is **seeded** — `--seed N` plus the
  gen-args now recorded in the source header reproduce it byte-for-byte, for free,
  forever. Source size buys nothing. Worse, the pressure to shrink pushes toward
  generating *small* programs, which makes the fuzzer's job easy and **the compiler's
  job easy** — the exact opposite of the point. As the user put it: 768 lines is
  "hardly the interface section of some complex unit"; vtables, inheritance chains and
  ctor/dtor ordering don't begin to strain a compiler until programs are large. (The
  shrinker didn't even work: chunk deletion breaks Pascal's block structure, so nearly
  every candidate failed to compile — 758 lines in, 758 out, budget exhausted.)
  **Replaced by trace-diff localization**, which answers the real question ("which
  construct diverged?") without touching program size: `--trace` emits the running
  checksum after every statement; the driver diffs two oracles' traces; the first
  differing checkpoint IS the guilty statement. O(1) compiles instead of O(lines), and
  it gets **better** with bigger programs instead of collapsing. On seed 111 it named
  statement 7 of 21 in seconds, where the shrinker had made zero progress in 45s.
  Corollary for the ladder below: **generate BIG programs.** Size is a feature.

  **(2) `--check` is the tool's gate, and it is fast and non-iterative.** pasmith's
  contract is "emits valid, well-typed objfpc" — so *FPC accepting the program IS the
  contract*, and that is a syntax/semantics question a compile answers in full. No
  running, no oracles, no iteration. 250 seeds / 0 rejects / ~6s for 50. Run it after
  every touch of `pasmith.py`. Divergence hunting is a separate, slower activity — do
  not conflate them.

  **OOP rung (the actual goal).** `--classes N` builds a *chain* of N classes, each
  overriding its parent's virtuals and calling `inherited`, so one call through a
  base-typed reference walks the whole chain. Objects are declared as the base and
  instantiated as random derived types, so no call is statically resolvable (a
  devirtualising optimiser that gets this wrong surfaces as an `-O`-level
  self-contradiction). Destructors fold into the checksum, making dtor **count and
  order** observable — a missed or doubled destructor changes the number. `--strs N`
  adds ansistrings: concat, `Copy` with live indices, `Length`, char indexing, strings
  as fields and method results. Verified both compilers agree on all of it before
  generating any of it.
  Three more generator bugs, all caught by the FPC gate: the ctor's `v` leaking into
  method scope; method bodies not covering all 8 integer types (which resurrected the
  constant-folding class via `leaf()`'s literal fallback); and `str_expr` emitting
  `o0.Name` *inside* `Name` — infinite recursion, breaking terminates-by-construction.
  Gate after fixes: 120 seeds at `--classes 5 --strs 3`, 0 rejects, 15s.

  **Status of divergences: parked, deliberately.** A 300-seed scalar run found 11
  pxx-vs-FPC checksum disagreements (all 11 with pxx self-consistent across -O0/-O2/-O3
  and FPC self-consistent — i.e. one systematic difference, not 11 bugs). Not chased:
  the user's call is that the tool comes first. They are reproducible from their seeds
  whenever someone wants them (`--seeds 100-400 --stmts 20 --vars 10 --depth 4`).
- 2026-07-13 — **v1 landed** (`tools/pasmith.py` + `tools/pasmith_run.py`, commit
  bab094f5). Scalar rung: all 8 integer widths + boolean + char, guarded div/mod,
  masked shifts, `if`/`case`/bounded-`for`, pure functions over a DAG call graph,
  single-checksum output, seeded. Oracles wired: `fpc -O-`/`-O2`, `pxx -O0/-O2/-O3`,
  and `--cross` for the QEMU targets. Line-wise delta-debug shrinker, gated on the
  divergence still reproducing *with the same signature* (otherwise a shrinker
  happily "reduces" a codegen bug into an unrelated compile error).
  CLAUDE.md Track T charter widened to "Tools & Testing" (commit 2b42f2fb): fuzzers
  now formally live in T alongside testmgr/twatch, and `tools/fuzz.sh` — previously
  orphaned under Track A — moves with them.

  **Two generator bugs found before any compiler bug**, both false-positive sources,
  and both worth recording because they are the failure mode that kills a fuzzer:
  1. **Constant folding.** All-constant subexpressions (`qword(231) shl 63`) overflow
     during *compile-time* folding, which FPC rejects as a hard **error** even under
     `{$Q-}` — that directive governs runtime wraparound, not constant evaluation.
     7/25 seeds were rejected by FPC. Fixed structurally rather than by patching:
     integer expression leaves are now always *variables*, never literals. A variable
     cannot be folded, so the class is unreachable by construction. (Literals survive
     only where they cannot overflow: initialisers, `for` bounds, case labels, masks.)
  2. **Clobbered `for` control variables.** Loop control vars were globals shared by
     main and every function, so a loop whose body called a function that also looped
     had its counter overwritten mid-flight. Modifying a `for` control var inside its
     own loop is **undefined** in Pascal — and the two compilers duly disagreed: FPC
     re-reads the counter from memory and spins forever, pxx keeps it in a register
     and terminates. A divergence *neither compiler owns*. It presented as 3
     "pxx vs FPC checksum mismatches" + 2 "FPC hangs", i.e. it looked exactly like a
     juicy compiler bug. Fixed: per-function local loop vars.

  This is the ticket's UB-free-BY-CONSTRUCTION invariant earning its keep on day one:
  every one of those 6 apparent findings was the generator's fault. **A finding from
  an unsound generator is worth nothing**, which is why the generator gets audited
  first (triage step (a)) and why v1 is scalar-only — prove the harness on ground
  where the answer is known before believing it about ansistring.
  After both fixes: 30/30 seeds clean.
- 2026-07-13 — filed. Origin: Csmith found real bugs in the C frontend; user asked
  whether an FPC-dialect equivalent exists. It does not — this builds it. Key design
  conclusions from that discussion, recorded so they aren't re-litigated at pickup:
  (1) the bugs are in IR, not the lexer/parser — the frontend is *loud* (syntax error,
  test fails immediately) while IR is *quiet* (silently wrong number), so a
  differential oracle is the only thing that sees them, and both the C and Pascal
  experiments landing in IR is not sampling bias;
  (2) cross-target differencing is structurally blind to uniformly-wrong lowering,
  which is why FPC-as-oracle is the point of this ticket;
  (3) a Pascal smith is *cheaper* than Csmith because Pascal has far less UB to dodge;
  (4) ansistring refcount/COW/lifetime is the highest-yield target and is
  unreachable from Csmith;
  (5) grammar fuzzing is the obvious wrong answer;
  (6) Track T is "Tools and Testing" — T owns the tool, findings file into the
  owning lane.
- 2026-07-13 — triage rule corrected after user pushback. The first draft said "FPC
  rejects the program → ALWAYS a pasmith bug"; that is wrong. FPC is the oracle, not
  the ground truth, and a fuzzer samples exactly the tail where FPC's own coverage is
  thinnest — so an FPC failure is a judgement call (read the code, read the spec,
  check the bugtracker), never a reflex dismissal. Finding a real FPC bug is an
  expected and welcome outcome of this tool, not an embarrassment to explain away.
  Rewrote the triage section as ordered *suspicion* rather than verdicts, added the
  selection-effect argument, and noted FPC-vs-itself (`-O0` vs `-O2`) as the oracle
  that needs no judgement at all.
