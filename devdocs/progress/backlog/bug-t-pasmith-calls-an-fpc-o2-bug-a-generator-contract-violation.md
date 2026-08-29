---
track: T
prio: 45
type: bug
blocked-by: []
summary: "classify()'s fpc-reject guard uses any() over (fpc-O0, fpc-O2), so ONE FPC arm failing to compile is declared a pasmith contract violation and returns before the fpc-self check that would correctly call it an FPC bug. Both recorded examples of the signature are FPC -O2 bugs where pxx is correct — a 100% misclassification rate on the bucket's whole history."
---

# pasmith calls an FPC `-O2` bug a generator contract violation

Found 2026-08-29 by frankC (Track C) while running the pasmith campaign. **Track
T owns `tools/pasmith_run.py`; this is reported, not patched.**

## The bug

`classify()` in `tools/pasmith_run.py` (~line 200):

```python
# A program FPC cannot compile is a pasmith bug (its contract is to emit
# only valid objfpc), and we cannot judge pxx against a broken oracle --
if any(results.get(n) == COMPILE_FAIL for n in ("fpc-O0", "fpc-O2")):
    return (True, groups,
            "FPC REJECTED THE PROGRAM -- pasmith contract violation (see ticket triage)",
            "fpc-reject")
```

`any(...)` fires when **either** FPC arm fails, and it `return`s — so it
short-circuits the `fpc-self` check thirty lines below, which already has the
right answer:

```python
if f0 is not None and f2 is not None and f0 != f2:
    note = "FPC CONTRADICTS ITSELF (-O0 vs -O2) -- an FPC bug, no judgement needed; pxx is not involved"
    cls = "fpc-self"
```

The comment's reasoning is sound *for the case it was written for* — if FPC
cannot compile the program at all, the generator broke its contract and there is
no oracle. It does not hold when only ONE arm rejects: FPC -O0 compiling and
running the program **proves the program is valid objfpc**, which is precisely
the contract the guard claims was violated.

## The repo already has the right model — this bucket just cannot reach it

`devdocs/progress/tstate/fuzz/fpc-bugs/README.md` states it outright: *"When FPC
contradicts itself (O1 vs O2/O3) the divergence is an FPC bug, not a pxx one."*
That directory exists, has a rigorously reduced example
(`fpc-o2-cse-rte216.pas`), and is where these belong.

So the concept, the destination and the note are all already implemented. The
asymmetry is only this: **FPC self-contradiction at RUNTIME is classified
correctly (`fpc-self_*`), and FPC self-contradiction at COMPILE TIME is not** —
the compile-fail guard catches it first and mislabels it.

## Every recorded instance is mislabeled

The signature `fpc-reject_compile-fail` has two examples in
`devdocs/progress/tstate/fuzz/LEDGER.json`, and **both are FPC `-O2` bugs where
pxx is correct.** Replayed at HEAD:

```
seed 362    fpc-O0, pxx-O0, pxx-O2, pxx-O3 : 16544526250867958718
            fpc-O2                          : <compile-fail>

seed 85029  fpc-O0, pxx-O0, pxx-O2, pxx-O3 : 271626998936251665
            fpc-O2                          : <compile-fail>
```

In both, every pxx optimisation level agrees with FPC's own `-O0` checksum. The
bucket's entire history is FPC bugs filed as "our generator is broken".

### Clean repro — seed 362, and it is small

```
tools/pasmith_run.py --seed 362 --vars 8 --funcs 3 --stmts 12 --depth 3 \
  --objs 3 --classes 0 --strs 0 --recs 0 --arrs 0 --enums 0 --shorts 0 \
  --excepts 0 --modeprocs 0 --intfs 0 --hier 0 --mptrs 0 --props 0 \
  --exdtor 0 --clsm 0 --checks 0 --consts 0
```

324 lines, and nearly every feature knob is **0** — a far simpler configuration
than seed 85029's 1412 lines with classes, properties, exceptions and hierarchies.
By hand on FPC 3.2.2 x86_64:

```
fpc -O2 s362.pas  ->  s362.pas(274,16) Error: Asm: byte value exceeds bounds 4294967295
                      s362.pas(324,1) Fatal: There were 1 errors compiling module
fpc -O-  s362.pas ->  324 lines compiled, 0.1 sec       (0 errors)
```

Line 274 is `g1 := byte(qword(longword(g1)));`. FPC's own assembler writer emits
an out-of-range operand at `-O2`. **The cast chain alone does NOT reproduce** — a
7-line program with the same statement compiles clean at both levels, so it is
context-dependent (register pressure at `-O2` is the obvious suspect). Not
reduced further: reducing an upstream compiler's bug is not this ticket's job,
and `fpc-bugs/README.md` shows what a real reduction costs.

For seed 85029 the *shape* is the harness's own (`fpc-O2 = <compile-fail>`, all
else agreeing); a hand `fpc -O2` gave `Error while linking`, which may be
environmental, so no claim is made that the two share a root cause.

## Why it matters

1. **It routes an FPC bug to the wrong lane.** "pasmith contract violation" says
   *fix the generator* — Track T work on a generator that is behaving correctly.
   The right destination is `tstate/fuzz/fpc-bugs/`, documented and possibly
   filed upstream.
2. **It is silent-by-design.** The run summary counts these as
   `N = FPC-rejected/generator bugs` and separates them from findings, so a
   sitting reports them as noise. The 2026-08-29 sitting printed
   `1 divergences (1 = FPC-rejected/generator bugs, ... 0 = NEW)` — which reads
   as a clean run, and contained a real FPC codegen bug.
3. It also suppresses a genuine pxx signal in principle: with the oracle
   declared broken, a pxx-side disagreement in the same program is not examined.

## Fix (Track T)

Make the contract-violation claim require **both** FPC arms — only then is there
genuinely no oracle:

```python
if all(results.get(n) == COMPILE_FAIL for n in ("fpc-O0", "fpc-O2")):
```

The single-arm case then falls through to the existing `fpc-self` logic, which
already produces the correct note and class. Worth checking the sibling
`pxx-reject` guard below it for the same shape while in there — it uses `any`
over the pxx arms, where one pxx level failing to compile while others succeed is
an optimiser bug rather than a frontend gap, and would currently be labelled the
latter. (Not measured; flagged because it is the same pattern one branch away —
`normalise-dont-special-case`'s "grep for the sibling" rule.)

## Not done here

Track C does not edit Track T's files. No change made to
`tools/pasmith_run.py`, and nothing written into `tstate/` (the run used
`PASMITH_FINDINGS_DIR` and a read-only `--ledger`, no `--ledger-inplace`).
