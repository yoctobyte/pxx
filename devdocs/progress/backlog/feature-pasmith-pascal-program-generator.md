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

### Triage rule — the two assumptions are NOT equally valid
Prior is overwhelmingly "pasmith emitted something it shouldn't have". Ordered:

| observation | conclusion |
| --- | --- |
| FPC **rejects** the program (compile error) | **Always a pasmith bug.** The generator's contract is that it emits only valid, well-typed `{$mode objfpc}` code. Never blame FPC here. |
| FPC compiles; pxx and FPC outputs differ | Suspect, in order: **(a)** pasmith emitted implementation-defined / UB code — audit the generator's UB-avoidance FIRST; **(b)** a pxx bug; **(c)** an FPC bug, last. |
| pxx targets disagree with each other | Backend/codegen bug (Track A) — same as `fuzz.sh` today. |
| pxx `-O0` vs `-O2`/`-O3` disagree | Optimizer bug (Track A / Track O lane). |

An FPC bug is a real possible outcome and worth reporting upstream when it happens —
but it must be **earned**, never assumed. Rule of thumb: if the minimized reproducer
isn't small enough and clean enough that you'd be comfortable posting it to the FPC
bugtracker, it isn't an FPC bug yet.

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
