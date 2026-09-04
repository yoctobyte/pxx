---
track: P
prio: 60
status: working
owner: frankA
type: perf
blocked-by: []
summary: "RE-MEASURED at HEAD -O2 (frankZ, 2026-09-04): the share has NOT dropped (9.92/9.94/10.35% over three runs vs the original 9.44%), so 440c822e6 did not remove it — but the premise is refuted for a THIRD time and the ticket is now mostly in the wrong lane. Disassembled, ParseFactorCore is 1,146,385 bytes of which 84% is managed-local TEARDOWN: exactly 150 runs of exactly 532 AnsiString releases (532 locals x 150 return points), carrying 36.1% of the function's samples. The 92-arm walk this ticket is NAMED for is 114 CaseEqual call sites carrying 3.2% of the function's samples = ~0.32% of a compile; a perfect hash dispatch has a generous ceiling of ~3% only if it also took all of CaseEqual's 3.1% body, and it carries the three documented hazards (name reassigned at 8 points, 25 duplicate names, the arms are not a ladder). The teardown is bigger, is Track A codegen, and is filed as perf-a-every-return-releases-every-managed-local-even-the-untouched-ones. WHAT IS LEFT FOR P is the ~0.3-3% dispatch question, ranked below its own hazards — not the 9.4% this ticket was opened for."
---

# `ParseFactorCore` walks a 92-arm name chain for every factor

Filed by the Track A session on
`perf-a-every-npy-compile-still-rebuilds-the-whole-nilpy-runtime`, which found
it while profiling the NilPy fixed cost. **Not touched** — `pasparser_expr.inc`
is Track P's file and A does not edit it.

## The measurement

Sampling profile of the real `-O2` compiler (`compiler/pascal26` self-hosted at
`13e196cc8`, `-O2 -g` so the profile is of the shipping configuration and not
the `-O0` that a bare `-g` silently selects) compiling a **zero-byte `.npy`** —
i.e. this is the cost of parsing `pylib.pas` + `pyeval.pas`, ordinary Pascal:

```
9.44%  ParseFactorCore     <- the largest named function in the compiler
4.96%  IRLowerAST
2.69%  UNameMatch
2.23%  ParseStatementAST
```

FPC `-pg` call counts (which are ours, where gprof's percentages are FPC's):

```
41,032 calls to ParseFactorCore
1,583,871 CaseEqual calls attributed to its frame   = 38.6 per factor
```

`compiler/pasparser_expr.inc:312` — the procedure runs to ~7,180 lines and
contains **92** `CaseEqual` sites, walked linearly. Every factor in every
program pays the full walk on a miss, and a miss is the common case: most
factors are ordinary identifiers, not `Length`/`Copy`/`Supports`/`round`/...

## Why it is the same bug as one already fixed next door

`bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost` found exactly this
shape in the text assembler and fixed it four times over: `AsmTextJccCode`
answering "no" by walking all 28 arms, `AsmRegNum` running its whole table on a
miss, `CaseEqual` scanning to the end of the string instead of bailing at the
first differing character. Same structure, same reason it is invisible — the
throughput curve stays perfectly linear, so nothing looks pathological.

## Shape of the fix (a hypothesis, not an instruction)

Dispatch before comparing: a fold-hash of `name` (`NameFoldHash` already exists
and is used elsewhere in the compiler) into a small table of intercept ids, or
at minimum a switch on the first character plus the length so that a miss costs
one comparison instead of 92. The arms themselves need not move.

The correctness hazard is the same one the existing chain relies on: **order**.
Some arms are reachable only because an earlier arm did not match, and a hash
dispatch loses that ordering for free. So the change is only safe if the arms
are mutually exclusive on the name — check that first, and where two arms share
a name, keep them in a nested chain under one hash bucket.

## Gate

Track P's: `make compiler/pascal26` byte-identical fixedpoint + your repro. The
strongest available check is **byte-identity of the emitted output** on a body
of Pascal that exercises the intercepts — `compiler.pas` itself compiles to a
9.1 MB binary and is dense with them, so `compiler.pas` in, `cmp` the two
outputs, is a very sharp oracle for "the dispatch resolves the same arm".

## What it is worth

~9.4% of every compile the Pascal frontend does, on every track. On the NilPy
fixed cost specifically it is ~0.27s of the current ~2.9s.

## 2026-08-30 (frankB) — the 92-arm walk is the SYMPTOM; each arm allocates a string

Binary: HEAD, self-host fixedpoint `faf762981c3c` (= pin v397). `perf` is
unavailable on this box (`perf_event_paranoid=4`, zero-sized capture), so this
is measured by direct A/B timing rather than by profile.

### The premise does not survive a look at `CaseEqual`

`CaseEqual` (`defs.inc:5322`) is **already optimal**: it compares lengths first
and returns, then bails at the first differing character. A miss against a
length-mismatched name is O(1). So "38.6 string compares per factor" should cost
almost nothing, and the arithmetic never worked — 1.58M O(1) compares cannot be
9.4% of a run.

### What it actually is: passing a LITERAL to an `AnsiString` parameter copies it

Five million calls each, same machine, same binary:

| form | ms |
| --- | --- |
| `if n = 'await'` — inline compare against a literal | **19** |
| `if n = lit` — inline compare against a variable | 22 |
| `ByConst('await')` — literal into a `const AnsiString` param | **543** |
| `ByVal('await')` — literal into a by-value `AnsiString` param | 576 |
| `ByConst(S_AWAIT)` — a typed `const S_AWAIT: AnsiString` | **30** |

**28x**, and it is a copy, not fixed call overhead — the cost scales with the
literal's LENGTH (5-char literal 791ms, 40-char literal 2151ms, variable 51ms
over 5M calls). Comparing against a literal *inline* is free; **passing** one to
a string parameter allocates and copies it, every call, even for `const`, where
by definition no copy is needed.

So `ParseFactorCore` is not slow because it walks 92 arms. It is slow because
**each arm it walks allocates and copies a string literal**, and it does that up
to 101 times per factor.

### This is not a ParseFactorCore bug and should not be fixed here

Every `CaseEqual(x, 'literal')` in the compiler pays it, and so does every pxx
program that passes a string literal to a string parameter. Filed as
[[perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call]]
with these measurements.

**Microfix vs overhaul, decided deliberately** per
`devdocs/dev/root-cause-over-microfix.md`: the microfix available in P's own
file is to hoist the 73 distinct literals into typed constants, which the table
above says would buy ~18x on these calls. **I am not doing it.** It is 101
mechanical edits in a 7,790-line function that become dead weight the moment the
Track A fix lands, and it would leave the same defect in every other caller and
in user code. The ticket's own suggested fix — hash dispatch — is a second
microfix: it reduces the NUMBER of copies rather than removing the copy, and it
carries a real correctness hazard (below) for a fraction of the win.

### If anyone does return to the dispatch idea, two facts it needs

1. **The arms are not an `else if` ladder.** They are ~54 independent `if
   CaseEqual(name, '...') and <more> then begin ... end` statements at indent 6,
   spread over 7,790 lines, plus ~47 nested deeper. There is no single chain to
   reorder.
2. **`name` is REASSIGNED at 8 points inside the function** (`:786`, `:1947`,
   `:3521`, `:3781`, `:3819`, `:3827`, `:5954`, `:7253`), so any hoisted
   per-name guard computed once at entry is silently WRONG after the first
   reassignment. This is the trap in the obvious implementation.
3. The order hazard the ticket warns about is real and larger than stated: of
   the 101 sites, **25 names appear more than once** (`Abs` 4x, `round` 3x,
   `hex`/`oct`/`trunc`/`frac`/`Eof`/`Chr`/`Succ`/`Concat`/`Copy` and the
   `__pxx*` intrinsics 2x each).

### Gate, unchanged and still the right one

`make compiler/pascal26` fixedpoint + `compiler.pas` in, `cmp` the two emitted
binaries. That oracle is what makes the Track A fix safe to land, since a
codegen change to literal marshalling must not alter a single emitted byte.

## Unblocked 2026-09-01 — it was invisible to the ranker, not waiting on anything

`tools/progress.sh check` had been reporting this for some time, in two
independent classes at once:

```
STALE-EDGE-HIDDEN: ... is in blocked/ but every blocker it names is closed
                   — ready/next never scan blocked/, so it is invisible
BLOCKED-BY-REJECTED: ... blocked by '...ansistring-parameter-is-copied-every-call'
                   which was rejected — it can never become ready
```

A **p60 that no path could ever surface.** The edge is dropped and the ticket is
back in `backlog-pascal/`.

**But do not read "unblocked" as "ready to implement."** The blocker was
rejected as SUPERSEDED, not as wrong — the optimisation was real and measured
(849ms → 84ms) and became worth nothing at `-O2` when `440c822e6` promoted
`EmitStaticLitHandle` thirty-six minutes later. That means the mechanism this
ticket blamed for the 9.4% is plausibly already handled at the default `-O`,
**by a different change than the one it was waiting for.** Nobody has re-measured
`ParseFactorCore` since. That measurement is the whole of the next step, and it
may well close this ticket.

## 2026-09-04 (frankZ) — the re-measurement this ticket asked for, and it moves the work to A

**The ticket's own first action, performed.** The answer is that the share has
NOT dropped, so it does not close on that test — but the mechanism is a third
thing, and it is not in `pasparser_expr.inc`.

### Provenance, because every share below depends on it

Binary built `-O2 -g` from `compiler/pascal26` at `a1536a832`
(`1968c7a7da57...`, `converged after 2 round(s)`). `code=10178328B`,
**identical to the plain default build** — so `-g` did not select `-O0` and this
is the shipping configuration, per the playbook's *"Profile the SHIPPING binary"*.
Workload: the same zero-byte `.npy`. `wall=1.87 user=1.81`, so the process is
pure user CPU and `<outside .text / vdso>` is sampling noise — it swung
**17.0% / 23.2% / 47.3%** across three identical runs, so every number here is
renormalised on in-`.text` samples, after which the spread is 0.43pp.

### 1. The share did not drop

| | run1 | run2 | run3 |
| --- | --- | --- | --- |
| `ParseFactorCore` | 9.92% | 9.94% | 10.35% |

Against the 9.44% that opened this ticket. **`440c822e6` did not remove it.**

It did do its job on the mechanism frankB blamed, though — re-running frankB's
own microbenchmark at HEAD `-O2`, min of 3: `ByConst('await')` is **51ms**
against a typed `const` at 30ms. frankB measured 543ms vs 30ms. So the
literal-copy went from **18x to 1.7x** and is no longer the story.

### 2. What the 10% actually is: 84% of the function is teardown

`ParseFactorCore` spans **1,146,385 bytes** — agreed by DWARF *and* by the
compiler's own `.map` (4143 entries, exactly one of which falls in the range),
so the extent is not a nearest-preceding-symbol artefact.

Disassembled, it contains **80,385 `call AnsiStrRelease` sites in exactly 150
runs of exactly 532** — mean = median = max = 532. That is **532 AnsiString
locals released at each of 150 return points**, unconditionally, touched or not.
The chain is **84% of the function's bytes** and takes **36.1% of the samples
that land in it**.

Confirmed independently by scaling rather than by sampling — a function with N
AnsiString locals that assigns one and returns, 2M calls, min of 3 interleaved
rounds: 4 -> 218ms, 64 -> 653ms, 256 -> 2192ms, 532 -> **4300ms**. Linear,
**3.87ns per local per call**, for slots that are nil and never touched. The
arithmetic back: 41,032 calls x 532 x 3.87ns = **84.5ms of 1870ms = 4.5%** of
the compile. Two methods that fail differently, agreeing.

**Filed as [[perf-a-every-return-releases-every-managed-local-even-the-untouched-ones]]
(Track A, prio 70).** `EmitManagedLocalCleanup`, `symtab.inc:12212`. Binary-wide
there are **308,112** such sites, ~36% of the compiler's 10.2MB `.text`. I have
written no code there — a shared epilogue or a liveness pass across six backends
is past one session, and A owns the shape. franka-29 has been told directly.

### 3. What is actually left for P, measured

The 92-arm walk this ticket is NAMED for: **114 `CaseEqual` call sites** inside
the function, carrying **3.2% of its samples = ~0.32% of a compile**.
`CaseEqual`'s own body is separately ~3.1% of in-`.text`, across all callers.

So a perfect hash dispatch has a **generous ceiling of ~3%**, and only if it
also took essentially all of `CaseEqual`'s body — while carrying the three
hazards already banked above (the arms are not a ladder; `name` is reassigned at
8 points; 25 names repeat). **It is not the 9.4% this ticket was opened for.**
Most of that 9.4% was always the teardown standing next to the walk.

**Not closed, and deliberately not microfixed.** The dispatch question is real
but is now ranked below its own hazards, and the honest next action is A's
ticket, not this one. Parked back to `backlog-pascal` unclaimed with a true
summary rather than held.

## Parked 2026-09-04

re-measured: the 9.4% is 84% managed-local teardown, not the arm walk; the real work is now Track A's perf-a-every-return-releases-every-managed-local-even-the-untouched-ones. What is left for P measures ~0.3-3% and is ranked below its own three documented hazards.

**Before resuming:** read the reason above, then the ticket body. If the reason does not tell you what would make this worth picking up again, establishing that is the first step -- a park is a handoff to a stranger who may be you.

## 2026-09-04 (frankA) — the dispatch is worth doing, and NOT for the reason in this ticket's title

**Re-claimed per the park note's instruction to read the reason first. It does
not tell me what would make this worth picking up — so, per that same note,
establishing it is the first step, and here it is.**

frankZ's ceiling stands and I am not re-arguing it: **~0.3–3% of a compile**,
against the 9.4% this ticket was opened for, with the teardown being the real
mass and Track A's. Nothing below disputes a number above.

**What the re-measurement did not have is who ELSE walks that chain.** Counted
at `f8b9e4394`, by listing:

- `ParseFactorCore` spans `pasparser_expr.inc:490–8491` — **8002 lines**.
- **All five named-type-cast dispatch sites from
  [[refactor-p-five-dispatch-sites-for-one-named-type-cast]] are inside it**,
  and they are five arms *of this chain*: `:1478` and `:1571` on the type
  keyword, `:4074` on `OrdinalNameToTk`, `:6725` on `BuiltinScalarTypeKind`,
  `:6434` on `FindTypeAlias`.

So the name-keyed resolver that refactor asks for and the dispatch this ticket
asks for **are the same edit seen from two sides.** A resolver consulted once
per factor both collapses the five doors and removes the walk; doing them
separately means writing the lookup twice.

### Which inverts the entry point

I told a peer earlier today to enter through this ticket because it carries the
higher prio (60 vs 35). **That was wrong and this note is the correction.**
After frankZ's measurement the perf case is ~0.3–3% ranked below three
documented hazards — it cannot carry the work. The refactor's case is
untouched by any of it and is a **correctness** argument with a measured
history: five doors, four separate bug rounds, each closing one door while the
next stayed shut, one of them (`bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree`)
a private 12-name table that DISAGREED with the shared one.

**Enter through the refactor. This ticket becomes a beneficiary, not a driver** —
the ~0.3–3% arrives for free with an edit justified on other grounds, which is
the only framing under which it is worth paying the three hazards.

### The hazards are the refactor's problem too, and one of them shrinks

`name` reassigned at 8 points, 25 duplicate names, arms that are not a ladder.
Those defeat *"hoist a per-name guard computed once at entry"*, which is the
obvious perf implementation. They do **not** defeat a resolver called at each
site with the name in hand — that keeps the reassignments and the ordering,
because it does not move when the question is asked, only how it is answered.
A hash dispatch that also relocates the arms is the version the hazards kill.

I confirmed the 8 reassignments independently (my first regex found 6 because it
only matched line-initial writes; `\bname\s*:=` finds 8, agreeing with frankZ —
and the agreement only became real after I fixed my instrument, which is worth
saying because it briefly read as a disagreement).

### Not implementing it tonight

`refactor-p-five-dispatch-sites-for-one-named-type-cast` is in `working/` with
my name on it and this pairing written into its body. **The claim is available**
— message me and it is yours, and take both or neither.

**Explicitly NOT part of this fact**, because a shared file invites the error:
[[refactor-p-three-hand-rolled-postfix-loops]]. Only 2 of its 5 Pascal copies
are inside `ParseFactorCore` at all, and they key on **a token appearing after a
primary**, not on a name — no name-resolver change reaches them. Those two
tickets look related and share no mechanism.

### One thing for whoever ranks

The summary is true and `prio: 60` predates it. A ticket whose own summary says
*"what is left measures ~0.3–3% and is ranked below its own hazards"* sitting at
p60 will keep surfacing from `next` ahead of the p35 that should actually be
entered first. I have not changed the number — it is frankZ's park and the
re-rank is theirs to make or refuse — but the mismatch is real and it is the
kind that survives because everyone assumes someone checked.
