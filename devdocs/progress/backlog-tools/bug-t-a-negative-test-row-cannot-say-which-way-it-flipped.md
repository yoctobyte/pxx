---
track: T
prio: 45
type: bug
status: backlog
blocked-by: []
found: 2026-09-05
found-by: frankH (mechanism, from a live instance it caused and fixed), frank-coordinator (filed)
summary: "In test-core's fail-fast recipe a `*_fail` row is `! ./$(COMPILER) ...` on one line and a `grep -q` for the expected message on the next, so THREE outcomes collapse into one indistinguishable failure: refused for the WRONG reason (fails at the grep), ACCEPTED (fails at the `!`), and the compiler CRASHED (fails at the `!`). All three read as 'the recipe stopped here'. Measured consequence, 2026-09-05: a *_fail test whose refusal had been deliberately lifted by its own feature commit sat at STEP 6 OF 15 and silently cost four fifths of the tier -- 3783 lines against 15253 once removed. The fix is to make the pair ATOMIC, not to add a helper. Positive control is available in the file: three shapes -- refused correctly, refused wrongly, accepted -- must produce three distinguishable verdicts."
---

# A negative test row cannot say which way it flipped

- **Type:** bug — Track T (harness). Filed at frankH's request; it found the
  mechanism from an instance it caused and fixed, and is not in this lane.
- **Status:** backlog, diagnosed not attempted

## The defect

A `*_fail` row is two recipe lines:

```
! ./$(COMPILER) test/foo_fail.pas /tmp/foo   # line 1
... | grep -q 'the expected message'         # line 2
```

**Line 2 carries the actual meaning, separately, where a reader does not connect
it to line 1.** So three distinct outcomes produce one indistinguishable result:

| what happened | which line fails | how it reads |
| --- | --- | --- |
| refused for the WRONG reason | the `grep` | "the recipe stopped here" |
| **ACCEPTED** (the refusal was lifted) | the `!` | "the recipe stopped here" |
| the compiler **CRASHED** | the `!` | "the recipe stopped here" |

**A `*_fail` test that starts COMPILING is indistinguishable, in a fail-fast
recipe, from a compiler that started CRASHING** (frankH). Those want opposite
responses — one is a stale assertion to delete, the other is a P0.

## Why it is worth p45 rather than a cleanup

**Measured, 2026-09-05.** `a11b2b18f` implemented `class var` in a named
top-level record and left `test_record_class_var_fail` asserting the blanket
refusal the same commit had lifted. It sat at **step 6 of 15**. `test-core`
stops at the first failing line, so **roughly four fifths of the tier was
UNVERIFIED rather than green, for every session, for as long as it stood** —
**3,783 lines blocked against 15,253 once removed** (frankH, `8727b1907`, green
end to end).

**And POSITION IS COVERAGE, which is the counter-intuitive part: in a fail-fast
recipe the cost of a red is not its severity, it is its INDEX.** The identical
defect at step 14 would have cost almost nothing. **Triage by severity
systematically mis-ranks these, and no ticket field records where in a recipe a
failure sits.**

## The fix, per frankH

**Not a new helper — make the existing pair ATOMIC.** One row that compiles,
captures, and asserts *refused **AND** for this reason* can say which way it
flipped. Mechanical, and it touches every `*_fail` row in the recipe, which is
why it is a ticket rather than a drive-by.

**The positive control is available in the file and must be written:** three
shapes — **refused correctly, refused wrongly, accepted** — must produce **three
distinguishable verdicts**. A guard that cannot tell them apart is the bug being
fixed, so a control that only checks "does it still fail" reproduces it.

## The class this belongs to

**The check belongs on the HARNESS, not on the author.** The author-side rule —
*when you narrow or lift a refusal, grep for the test asserting the old one* —
depends on remembering at exactly the moment you are pleased with yourself.
**A `*_fail` row that can name its own transition needs no memory.**
