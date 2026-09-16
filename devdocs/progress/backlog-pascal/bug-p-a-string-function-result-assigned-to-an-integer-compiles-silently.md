---
slug: bug-p-a-string-function-result-assigned-to-an-integer-compiles-silently
title: "A string-returning function's result assigned to an Integer compiles with no diagnostic"
track: P
prio: 30
type: bug
status: open
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
