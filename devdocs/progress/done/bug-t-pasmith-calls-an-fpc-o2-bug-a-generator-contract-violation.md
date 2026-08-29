---
track: T
prio: 45
type: bug
blocked-by: []
summary: "classify()'s fpc-reject guard uses any() over (fpc-O0, fpc-O2), so ONE FPC arm failing to compile is declared a pasmith contract violation and returns before the fpc-self check that would correctly call it an FPC bug. Both recorded examples of the signature are FPC -O2 bugs where pxx is correct — a 100% misclassification rate on the bucket's whole history."
status: done
owner: frankC
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

## GRANT: frankC holds `tools/pasmith*.py` for this fix — frank-coordinator, 2026-08-29

Filed here rather than left in message traffic, because **an unfiled grant does
not read as missing, it reads as covered** — a neighbouring T ticket covers the
same directory and nothing would show the gap.

**Scope, by file and not by lane:** `tools/pasmith.py` and
`tools/pasmith_run.py`, plus `tstate/fuzz/fpc-bugs/**` for reclassifying the two
recorded entries. **Not** `tools/testmgr.py`, **not** `tools/twatch*.py`, **not**
the tier composition — those stay with Track T's own agent, which is being
dispatched to a disjoint item (the deploy/provisioning gap) at the same time.

**Why frankC and not T's agent:** frankC produced the diagnosis in a 452-program
sitting and holds the context — the short-circuit in `classify()`, the two seeds
(362, 85029) that replay it, and the fact that both recorded examples of the
signature are the same shape. Handing it to another session would re-derive that
at full cost. Track C's own queue is dry and its head items route to A, so frankC
is genuinely free rather than being pulled off ranked work.

**The grant is provisional in the usual way:** verify the file map before
editing, and report back if the boundary above is wrong. A grant is a claim
about what is permitted, and like any claim it can be wrong about the tree.

### Also in scope: the sibling guard, because the rule says to look

frankC flagged, **without measuring it**, that the `pxx-reject` guard immediately
below uses `any` over the pxx arms the same way — so one pxx level failing to
compile while others succeed would be labelled a frontend gap when it is an
optimiser bug. Treat that as a lead, not a finding, and settle it by reading the
code while you are in the file. Same double-case rule that produced this ticket:
**fix one arm, grep for the sibling before closing.**

## RESOLVED 2026-08-29 (frankC, under the Track T grant `c9f1df44f`)

Boundary verified before editing, as the grant required: `working/` held only
`bug-a-the-fpc-seed-canary-...` and `feature-rust-option-type`, no open ticket
named pasmith, and the last four commits to `tools/pasmith*.py` were all landed
Track T work. The file map in the grant was correct.

### The fix is one idea, not four branches

**A compile failure is just another value the oracles can disagree about.** Once
that is true, the checks that were already in `classify()` handle it with no new
bucket:

- `fpc-reject` (generator contract violation) now requires **all** FPC arms to
  fail. If one level compiles the program, the contract was *kept* — the program
  is provably valid objfpc by the oracle's own `-O0` — and the disagreement is
  FPC's, which `fpc-self` already says.
- `pxx-reject` (frontend gap) likewise requires **all** pxx arms to fail. Some
  failing and some not means the frontend accepted the program and the optimiser
  broke it: `pxx-self`, an optimiser bug (Track A/O), not a frontend gap
  (Track A/P).

### The trap that made this more than a one-word change

Flipping `any`→`all` alone would have **silently deleted the finding** rather
than fixing it. The next guard was:

```python
real = {k: v for k, v in groups.items() if k != COMPILE_FAIL}
if len(real) <= 1: return False, groups, "", ""
```

It drops the compile-fail arm and asks whether the survivors agree. For seed 362
the survivors *do* agree — `fpc-O0` and all three pxx levels give the same
checksum — so it would have returned **no divergence at all**. That is strictly
worse than the mislabel this ticket was about: a mislabelled finding is still in
the ledger, a dropped one is gone.

It is now `if len(groups) <= 1`, i.e. "did every oracle produce the same value",
with COMPILE_FAIL an ordinary value. That is the same normalisation as the fix
itself, applied to the predicate.

### And the sibling the caller had

Routing partial compile failures to `fpc-self`/`pxx-self` sends them past
`localize()`, which trace-diffs two **running** programs. A non-compiling arm's
trace is the single line `<compile-fail>`, so every one of these would have
reported a confident, wrong *"first divergence at checkpoint 0"*. The caller
keyed on `cls in ("fpc-reject", "pxx-reject")` and then looked up
`LAST_ERR["fpc-O0"]` — the arm that **succeeded**. Both are now keyed on the
fact rather than the class name:

```python
failed = sorted(groups.get(COMPILE_FAIL, []))
if failed: kind = LAST_ERR.get(failed[0]) or "compile-fail"
```

### Measured, both arms and every pre-existing path

Nine classification cases through the real `classify()`:

| results | before | after |
| --- | --- | --- |
| fpc-O2 fails, all else agrees | `fpc-reject` "contract violation" | **`fpc-self`** |
| both fpc arms reject | `fpc-reject` | `fpc-reject` (unchanged, correct) |
| pxx-O2 fails, pxx-O0 fine | `pxx-reject` "frontend gap" | **`pxx-self`** optimiser bug |
| all pxx reject | `pxx-reject` | `pxx-reject` (unchanged, correct) |
| everyone agrees | clean | clean |
| fpc runtime self-contradiction | `fpc-self` | `fpc-self` |
| pxx runtime self-contradiction | `pxx-self` | `pxx-self` |
| pxx vs fpc, each self-consistent | `pxx-vs-fpc` | `pxx-vs-fpc` |
| cross target fails to build | `pxx-reject` | **`pxx-cross`** backend bug |

End to end on the two real seeds — and note they now get **different**
signatures, where the old bucket had deduplicated two unrelated FPC bugs into
one:

```
seed 362    sig=fpc-self_asm-byte-value-exceeds   (was fpc-reject_compile-fail)
seed 85029  sig=fpc-self_error-while-linking      (was fpc-reject_compile-fail)
```

The signature now carries FPC's own diagnostic instead of the opaque
`compile-fail`, which is what makes them distinguishable.

### Gate

- 9/9 classification cases correct, including all five pre-existing behaviours
- `--check 20`: 20 seeds, **0 rejected by FPC** (generator gate unaffected)
- End-to-end batch, seeds from 5000: **170 programs, 0 divergences**, runner healthy
- Both seeds replayed; after reclassifying the ledger, seed 362 reports
  `fpc-self_asm-byte-value-exceeds (known, hit 2)` and
  `0 = FPC-rejected/generator bugs`

### Also landed

- **Ledger reclassified** (`tstate/fuzz/LEDGER.json`): the dead
  `fpc-reject_compile-fail` signature retired, its two examples re-filed under
  their real signatures with `reclassified_from` recorded, `status: ticketed`.
  Written with `save_ledger()`'s exact format (`indent=2, sort_keys=True`) — a
  first pass at `indent=1` produced a 2900-line spurious diff and was redone.
- **The FPC bug documented** in `tstate/fuzz/fpc-bugs/README.md` with its
  reproducer committed as `fpc-o2-asm-byte-value-exceeds.pas`. The `.pas` is
  committed rather than left as a seed because `--seed 362` only reproduces
  against the pasmith that generated it, and `tools/pasmith.py` changes often.
  Recorded as **NOT checked against FPC trunk** — the sibling entry was, and the
  difference matters before anyone files upstream.

### Not done

`tools/pasmith.py` (the generator) was not touched — nothing was wrong with it,
which was the point. Nothing outside the granted file map: no `testmgr.py`, no
`twatch*`, no tier composition.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
