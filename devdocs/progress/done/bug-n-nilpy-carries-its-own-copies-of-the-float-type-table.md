---
slug: bug-n-nilpy-carries-its-own-copies-of-the-float-type-table
track: N
prio: 30
type: bug
blocked-by: []
summary: "`compiler/pyparser.inc` holds three private copies of the builtin float mapping, all hard-wiring `real` to `tyDouble`, and one of them additionally collapses `single` and `extended` to Double. The Pascal frontend just had the same duplication fixed; NilPy kept its own, so `Real` there is Double even on targets where it is Single."
status: done
owner: frankC
---

# NilPy carries three private copies of the float type table

## Sites

All in `compiler/pyparser.inc`:

| line | shape | wrong how |
| --- | --- | --- |
| 966 | `tkReal_T, tkSingle_T, tkDouble_T, tkExtended_T: Result := tyDouble;` | collapses **four** distinct types to one — `Single` and `Extended` lose their identity, not just `Real` |
| 43036 | `else if CaseEqual(tiName, 'double') or CaseEqual(tiName, 'real') then tiTk := tyDouble` | `real` hard-wired |
| 43055 | `tkReal_T: tiTk := tyDouble;` | `real` hard-wired |

Lines 43036 and 43055 are line-for-line the shapes just fixed in
`pasparser_lval.inc` and `pasparser_expr.inc` under
[[bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets]] — the same
two tables, copied into the second frontend. `RealTypeKind` (`util.inc`) already
exists and is what they should call.

Line 966 is a different and larger claim: it says a `Single` is a `Double`.
Worth measuring before assuming it is a bug — it may be a deliberate
"NilPy has one float type" simplification, in which case it needs a comment
saying so rather than looking like the same copy-paste as the other two.

## Why it is filed as N and not A

The Pascal frontend is correct as of `ae2c3aae2`. This is NilPy's own copy, so
the blast radius is NilPy programs on xtensa/riscv32, where `Real` is Single:
`SizeOf` and RTTI would report Double over 4-byte storage — the same
silent-wrong-size defect, one frontend over.

Not urgent: NilPy on an ESP target is a narrow combination, and nothing is known
to depend on it today. It is filed because the defect is *found and located*,
not because it is scheduled.

## The reason this ticket exists at all

Spotted while fixing the Pascal side, mentioned in passing, and initially **not**
filed — Track N is outside the A/P/C focus, so it read as out of scope. Wrong
call: scope governs what gets *worked*, not what gets *recorded*. An unfiled
finding is one that has to be rediscovered. Raised by the owner (2026-08-27):
*"obviously if we find bugs they should be filed"*.

## Gate

The three sites resolve through one routine; a NilPy program on riscv32 reports
`SizeOf(Real) = 4`; line 966 either distinguishes the four types or carries a
comment justifying why it does not. Self-host byte-identical.

## Fixed 2026-09-02 — and the observable is currently UNREACHABLE

All three sites now call `RealTypeKind`, so the third private copy of the
mapping is gone. Line numbers had moved (966 -> 1080, 43036 -> 46441,
43055 -> 46459); located by content instead.

**The blast radius this ticket states cannot be reached today.** It says the
cost is "NilPy programs on xtensa/riscv32, where `Real` is Single" — and those
are exactly the two targets where NilPy does not compile at all:

```
--target=riscv32   error: target riscv32: a heap arena needs mmap, which this
                          profile has not
--target=xtensa    error: target xtensa: a heap arena needs mmap, which bare
                          metal has not
```

Both name [[bug-a-nilpy-on-cross-targets-four-remaining-walls]], which is open
and records riscv32/xtensa as `a heap arena needs mmap`. `RealTypeKind` returns
`tyDouble` on every target NilPy can currently build for, so **the fix is a
provable no-op today** — verified: byte-identical code/data sizes on x86-64 and
identical output under qemu-arm, plus an existing NilPy test still passing.

That is why this is fixed rather than filed at a low prio or rejected. Per
CLAUDE.md an observable no compiling program can reach belongs in `rejected/`,
but this one is not unreachable in principle — it is gated behind another open
ticket, and becomes live the moment those walls come down. Removing the
duplicate now costs nothing and means the cross-target work does not inherit a
latent wrong answer.

## The `Single`/`Extended` collapse: measured, NOT resolved

This ticket asked for line 966 to be measured before being assumed a bug. It is
left collapsing `tkSingle_T`/`tkDouble_T`/`tkExtended_T` to `tyDouble`,
deliberately, and the reason is a NilPy semantics question rather than a
lookup: CPython has ONE float type, so "NilPy has one float type" is a coherent
position, and changing `Single` to `tySingle` in return-type inference is a
behaviour change rather than a correction.

What the measurement DID turn up is a separate inconsistency worth recording,
because it is not what either reading predicts — **the two annotation paths
disagree about which of these names they can read at all**:

```
def main():                     def gr() -> Real:    (no warning — read)
    a: Single = 1.5   read      def gs() -> Single:  warns "cannot read"
    b: Double = 1.5   warns     def gd() -> Double:  warns "cannot read"
    c: Real   = 1.5   warns
```

A VARIABLE annotation reads `Single` and degrades `Real`/`Double` to Any; a
RETURN annotation reads `Real` and degrades `Single`/`Double`. Neither is the
"one float type" story and neither is the "three types" story. That belongs to
whoever settles the float-type question, and is not fixed here.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 866d9d5e8.
