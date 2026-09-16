---
slug: bug-p-a-string-function-result-assigned-to-an-integer-compiles-silently
title: "A string-returning function's result assigned to an Integer compiles with no diagnostic"
track: P
prio: 30
type: bug
status: done
owner: ""
found-by: franks-ee
created: 2026-09-16
tags: [typecheck, strings, missing-diagnostic, silent-wrong-value]
blocked-by: []
summary: "`n := F('x')` where `F: AnsiString` and `n: Integer` compiles with no error and prints the string's POINTER as a number (a different number each run -- 2107637832, -1413480376). fpc refuses it: `Incompatible types: got \"AnsiString\" expected \"LongInt\"`. The same assignment from a string VARIABLE is correctly refused (`n := s` gives `incompatible types: cannot assign AnsiString to Integer`), so the check exists and the function-RESULT path does not reach it. ShortString results too, and qualified or unqualified alike. NOT caused by the qUnit const fix (dc3fedb0a) -- the pinned pre-fix compiler does it identically; that fix merely stopped a shadowing const from intercepting the expression and so made it visible. RANKING TENSION STATED DELIBERATELY: CLAUDE.md says accepting what fpc rejects is not a defect, and `n := F('x')` for a string-returning F is only ever a mistake, which argues rejected/. The counter-argument, and the reason this is filed rather than rejected, is that this is not dialect breadth -- it is a MISSING CHECK that turns a typo into a plausible number instead of an error, and the FPC-corpus work is exactly where a typo would be swallowed. Whoever ranks it should settle that, not re-derive it."
---

# A string function result assigned to an Integer compiles silently

## Repro

```pascal
program v4;
function F(const a: AnsiString): AnsiString; begin F := 'r'+a; end;
var n: Integer;
begin n := F('x'); WriteLn(n); end.
```

pxx: compiles, prints a pointer as a number. fpc 3.2.2:
`v4.pas(4,12) Error: Incompatible types: got "AnsiString" expected "LongInt"`.

## The boundary, measured

| spelling | pxx | fpc |
| --- | --- | --- |
| `n := s` (AnsiString **variable**) | refused, correct message | refused |
| `n := F('x')` (AnsiString **result**) | **compiles** | refused |
| `n := G` (ShortString result, no args) | **compiles** | refused |
| `n := qunit.Thing('x')` (qualified result) | **compiles** | refused |

So the assignment check is present and correct for a variable operand and is
not reached for a call operand. Qualification is irrelevant -- it was only how
this was found.

## How it was found, which is the part worth keeping

It surfaced as the ONE row that still diverged from fpc after
bug-p-a-unit-qualified-reference-is-captured-by-a-same-named-string-const was
fixed, in a 17-row differential matrix. The honest reading of a single
post-fix divergence is "my change caused it", and that reading TERMINATES the
search -- so it was attributed to a range before being attributed to the
change, per CLAUDE.md's own rule about the unfavourable direction. The pinned
pre-fix compiler reproduces it exactly, on a program with no qualifier and no
shadowing const in it (`v4` above). It had been MASKED here: the shadowing
constant was intercepting the expression and producing a (coincidentally
correct) type error of its own.

**A pre-existing defect can be hidden by a second defect in front of it, and
fixing the front one looks exactly like causing the back one.**

## Where to look

The variable path produces `incompatible types: cannot assign AnsiString to
Integer`, so the message and the check both exist. The question is which
assignment-compatibility site the call-result path takes instead, and whether
it is the same seam as any other "result of a call" typing gap.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## FIXED 2026-09-16 — and the RANKING QUESTION IS SETTLED BY MEASUREMENT

This ticket deliberately left its own ranking unresolved: a missing check (bug)
versus accepting-what-fpc-rejects (not a defect, per CLAUDE.md). **It is the
first, and one command decides it rather than an argument.** The same assignment
from a string VARIABLE was ALREADY refused, identically to fpc:

| spelling | pxx before the fix | fpc 3.2.2 |
| --- | --- | --- |
| `n := s` (variable) | `cannot assign AnsiString to Integer` | refused |
| `n := F('x')` (call result) | **compiles, prints 1660944456** | refused |

So this was never dialect breadth. The check existed and one spelling of the
source did not reach it — an inconsistency inside our own type checker, which
produces a silently wrong value from an ordinary typo.

**Cause.** `AssignSideKind` (ir.inc) had arms for `AN_IDENT`, the literals,
`AN_BINOP` and `AN_INDEX`/`AN_FIELD`/`AN_DEREF`, and none for a call — so it
returned False, `AN_ASSIGN`'s check short-circuited, and it looked exactly like
a check that had fired and passed. **The fourth instance of that function's one
shape, and its own header predicted it:** *"a side this function cannot type is
a side the rule never sees, and the failure is silent in the safe direction."*

**Fix.** The three call kinds joined the existing arm's case label and needed no
new logic. The parser already resolves the result type into `ASTTk` — verified
with `PXXDBG=a.ast` rather than assumed, the repro's `AN_CALL` node carries
`tk=23` — which is where that arm already reads, and its dyn-array, record and
reference-shaped guards all ask the node rather than an lvalue.

**All three spellings, not `AN_CALL` alone.** `AN_CALL`, `AN_VIRTUAL_CALL` and
`AN_INTF_CALL` are one family carrying the `Procs[]` index in `IVal`; ir.inc
enumerates exactly this trio twice already and says an enumeration listing only
`AN_CALL` *"is wrong for every override"*. The fail test writes all three, the
virtual one dispatched through a base-class reference so it cannot devirtualise
into the direct case — a one-row test would have passed a one-spelling fix.

**Both controls asserted, neither assumed.** The PINNED v410 compiler accepts
the fail file and prints `4265512` — a pointer as a number — in all three
spellings, so the guard genuinely reddens on the unfixed compiler. And nine
legal call-result assignments still compile and run, with `.expected` taken from
fpc's own output on the same source: a false REJECT of working code would be a
worse defect than the false accept being fixed, and that is the half most likely
to go wrong when a type check gains a node kind.

`test/test_call_result_assign_typecheck_positive.pas` and
`…_fail.pas`, both wired. `make compiler/pascal26` converged after 1 round;
`gate.sh quick` GREEN, read off the log rather than the wrapper's exit code.

**`compiler/**`, so INERT UNTIL THE NEXT PIN** — nothing on `$(PXX_STABLE)`,
`make lib-test` included, sees this yet.
