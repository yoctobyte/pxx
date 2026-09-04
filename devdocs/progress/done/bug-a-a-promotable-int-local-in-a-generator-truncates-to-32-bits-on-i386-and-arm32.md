---
track: A
prio: 60
type: bug
blocked-by: []
summary: "FIXED, and MY OWN PREMISE WAS WRONG: this is not an i386/arm32 bug. A promotable int is a {tag, payload} pair and the stackless-generator slot allocator gave it ONE word, dropping the tag, so a value past the inline tier came back as its inline bits -- on EVERY target, only the threshold moves. I filed it as 32-bit-only because 6000000042 is past 2^32 and not past 2^63; a multiply loop past 2^63 is wrong on x86-64 and aarch64 too. Fixed with the variant arm's blob-copied slot region, plus a width assert on the fall-through that accepted it."
status: done
owner: frankb-78
---

# A promo-int local in a generator truncates to 32 bits on i386 and arm32

- **Track A.** Measured 2026-09-04 by frankb-78 while writing the guard for
  `bug-a-a-managed-local-that-survives-a-yield-is-released-at-every-yield-on-every-cross-target`.
  Found because the first draft of that test carried a promo-int local and the
  row stayed red after that fix, for this unrelated reason.

## The repro

```python
def gen(k):
    n = 0
    i = 0
    while i < k:
        n = n + i * 1000000007
        yield n
        i = i + 1

for v in gen(6):
    print(v)
```

| | 4th value | 5th | 6th |
| --- | --- | --- | --- |
| CPython / x86-64 / aarch64 | 6000000042 | 10000000070 | 15000000105 |
| i386, arm32 | **1705032746** | 5705032774 | 6410065513 |

`6000000042 - 2^32 = 1705032746` exactly, and the first value to exceed 2^32 is
the first one wrong. The truncation is not cumulative in the obvious way — the
5th and 6th are each computed from a truncated predecessor.

## Where it is NOT

- **Not the arithmetic.** The identical loop at module scope prints all six
  values correctly on i386 and arm32 (verified both at HEAD and on pin v403).
- **Not the release path.** Reproduces unchanged on pin v403, which predates
  every scope-exit change of 2026-09-04.
- **Not 32-bit targets as a class.** It is i386 and arm32; aarch64 is correct,
  and riscv32/xtensa cannot run NilPy at all
  (`bug-a-nilpy-on-cross-targets-four-remaining-walls`).

So the suspect is the generator instance's checkpoint/restore of a promotable-int
local: a promo slot is a machine word plus a tier, and a 32-bit target that saves
or restores only the word loses exactly the heap tier — which is the observable.

## The guard this needs

The repro above, wired on i386, arm32, aarch64 and x86-64 with CPython's output
as the expectation. **Do not fold it into the managed-local yield test** — that
one deliberately carries no promo-int local for exactly this reason, and its
comment says so.

## Correction — my own premise was wrong, and x86-64 was NOT correct

This ticket was filed with *"aarch64 and x86-64 are correct"*. **They are not.**
I measured `6000000042`, which is past 2^32 and not past 2^63, so it left the
inline tier on a 32-bit target and stayed inside it on a 64-bit one. The
instrument answered honestly about the value I gave it; the value was the
problem. Measured 2026-09-04, same day, pin v403 unchanged:

```python
def gen(k):
    n = 1
    i = 0
    while i < k:
        n = n * 1000003
        yield n
        i = i + 1
```

x86-64 goes wrong from the 5th value (`-4442939197172260078964685` against
`1000015000090000270000405000243`), and so does aarch64. **The defect is on
every target and only the THRESHOLD moves.** This is the shape CLAUDE.md
records under "nothing observably differs is a claim about one target" — except
inverted: I had TWO targets disagreeing and read that as a target split, when it
was one bug with a width-dependent trigger. A cross-target difference is not
evidence of a target-specific cause.

The "same arithmetic at module scope is correct" half of the original claim
holds and is what rules out the bignum tier itself: all eight values print
correctly at module scope on x86-64 AND i386.

## Resolved — a {tag, payload} pair needs a blob-copied slot region

`pasparser_stmt.inc`'s slot allocator has arms for by-ref, variant, string and
record, and then a **fall-through that gives everything else one word**. A
promotable int is 8 bytes (`tyPromoInt32`) or 16 (`tyPromoInt64`) and fell into
it, so the checkpoint persisted the payload and dropped the tag.

The fix is the variant arm's shape: reserve `(TypeSlotSize(tk) + 7) div 8`
words and blob-copy through `SlBlob`/`SlUnblob` in `SLSaveLocals` /
`SLRestoreLocals`. Bitwise is refcount-neutral, and the ordering constraint the
variant arm states applies unchanged — exactly one of the frame copy and the
instance copy is live at a time.

**The promotable-int family already had a rule that should have caught this**,
and it is quoted in `TypeSlotSize`'s own comment: *"a promotable int is a {tag,
payload} struct, not a machine word ... anything that must handle it asks for it
by name — an unhandled site errors instead of miscompiling."* This site did not
ask and did not error, because a fall-through accepts everything. So the fix
also makes that arm state its claim:

```pascal
    if TypeSlotSize(tk) > 8 then Error(... 'is wider than the one-word
      persistent slot this arm gives it' ...);
```

A kind wider than a word reaching there is the same defect in a different type
(`tyExtended` is the next one in line), and the family's contract is that it
errors rather than miscompiling.

**The test is `test/test_nilpy_generator_promo_int_survives_yield.npy`**, wired
on x86-64, i386, aarch64 and arm32, carrying BOTH thresholds so no target's
inline width can make it vacuous. The pin control fires on **all four** — which
is the correction above, made assertable.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e60e61437.
