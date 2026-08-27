---
slug: bug-n-nilpy-carries-its-own-copies-of-the-float-type-table
track: N
prio: 30
type: bug
blocked-by: []
summary: "`compiler/pyparser.inc` holds three private copies of the builtin float mapping, all hard-wiring `real` to `tyDouble`, and one of them additionally collapses `single` and `extended` to Double. The Pascal frontend just had the same duplication fixed; NilPy kept its own, so `Real` there is Double even on targets where it is Single."
status: backlog
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
