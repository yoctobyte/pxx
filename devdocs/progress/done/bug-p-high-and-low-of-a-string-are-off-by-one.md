---
slug: bug-p-high-and-low-of-a-string-are-off-by-one
title: "`High(s)` and `Low(s)` over a string answer 0-based bounds for a 1-BASED string"
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "`s: AnsiString = 'qxy'` — fpc says Low(s)=1, High(s)=3; pxx says 0 and 2. pxx strings ARE 1-based (s[1] is 'q', exactly as in fpc), so `for i := Low(s) to High(s) do Write(s[i])` reads s[0] and misses the last character. Silent wrong value in idiomatic code, in a shape that compiles today."
---

# Measured against fpc 3.2.2

```pascal
var s: AnsiString;
begin
  s := 'qxy';
  WriteLn(Low(s), ' ', High(s));   { fpc: 1 3   pxx: 0 2 }
  WriteLn(s[1]);                   { fpc: q     pxx: q    <- both 1-based }
end.
```

| expression | fpc | pxx |
| --- | ---: | ---: |
| `Low(s)` | 1 | **0** |
| `High(s)` | 3 | **2** |
| `s[1]` | `q` | `q` |
| `Length(s)` | 3 | 3 |

The third row is the whole ticket: **pxx indexes strings from 1, exactly as fpc
does**, so answering 0-based bounds is not a dialect choice, it is an
inconsistency with pxx's own indexing. `for i := Low(s) to High(s) do Write(s[i])`
— the canonical spelling — reads `s[0]` and drops the last character. It
compiles, runs, and is wrong.

## Root cause — an exact line

`compiler/pasparser_expr.inc`, the tails of the `High` and `Low` arms. Every
fold above them is guarded on the operand being an array or an ordinal; a string
falls through to:

```pascal
{ High }  CurASTNode := Length(x) - 1
{ Low  }  CurASTNode := 0
```

which is the right answer for a 0-based dynamic array and the wrong one for a
1-based string. The fallback was written for arrays and inherited strings by
accident.

## The literal is a DIFFERENT case — do not "fix" it to match

fpc treats a bare string LITERAL as a 0-based array-of-char constant and a
string EXPRESSION as a 1-based string:

| expression | fpc |
| --- | ---: |
| `Low('abc')` / `High('abc')` | 0 / 2 |
| `Low('ab' + s)` / `High('ab' + s)` | 1 / 3 |
| `High(F(1))`, F returning `AnsiString` of length 4 | 4 |

So the existing `Length-1` / `0` tail is exactly right for a bare literal and
exactly wrong for everything else string-shaped. Any fix must keep both.

## …and both arms currently REFUSE a non-ident operand

```pascal
if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type');
```

so `High('abc')`, `High('ab' + s)` and `High(F(1))` cannot be written at all —
all three legal in fpc. (`High` over a proc CALL was fixed on 2026-08-25 by
`compat-pascal-index-a-function-call-result`, which routes a proc NAME through
`ParseExpr`; a literal or a parenthesised expression still hits this line.)
Widening the guard and getting the base right are one job.

`Length` had the sibling defect and it is already fixed —
[[bug-p-length-of-a-string-literal-plus-anything-does-not-parse]], whose ticket
says in as many words: *"`High` has the same class of defect one layer worse …
do not close this one without looking."* This ticket is that look.

## Gate

Track P's. A test wired into `test-core` with every row of both tables above,
each diffed against fpc 3.2.2 — including the ones that work today, since the
fix moves them onto a different path. Watch the shortstring / `string[N]` and
`array of Char` spellings too: they have their own bases and their own folds
further up the same arms.


## RESOLVED 2026-08-25 — three bases, not two, and fpc gives all three

The tail both arms fall into was written for arrays and inherited strings by
accident. It now branches on the operand's kind:

| operand | bounds | how |
| --- | --- | --- |
| MANAGED string (`AnsiString`) | `1 .. Length(s)` | Low folds to 1; High emits the runtime `Length` call with **no** `- 1` |
| FROZEN string (`string[N]`, `ShortString`) | `0 .. declared CAPACITY` | Low keeps 0 (index 0 is the length byte); High folds to `SymStrCap[idx]`, or `DEFAULT_STR_CAP` when the row says 0 |
| array (incl. `array of Char`) | unchanged | every array arm above already claimed those |

Note the frozen row is the **capacity**, not the current length — fpc says 10 for
`sh: string[10]` holding two characters, and 255 for a `ShortString`. The old
tail answered 1 and 2.

Measured against fpc 3.2.2, not reasoned about; the three-base split is what the
measurement showed, and it is not what I expected going in.

### Two guards that are load-bearing

- **`IsNodeArray(valNode)` excludes array operands.** `AllocDynArray` stores the
  ELEMENT type in `Syms[].TypeKind`, so a `array of AnsiString` reads as
  `tyAnsiString` on its own symbol; without this guard `High(sa)` over a
  4-element array would have answered `Length` instead of `Length - 1`. That row
  is in the test.
- **The frozen arm additionally requires a plain VARIABLE**, because that is the
  only operand whose declared capacity is on hand.

### Known gap, left as-is on purpose

`High(G)` where `G: TSA` returns `string[6]` answers **1** (the old
`Length - 1`); fpc says 6. There is no `ProcRetStrCap` row, and defaulting to
255 there would turn today's too-SMALL bound into a too-LARGE one — a loop
reading past the end instead of stopping early, which is the worse of the two
wrongs. Adding the capacity to the proc row is a small Track A metadata change;
until then the frozen arm declines the operand rather than guessing. The test
says so in its header and does not assert the row.

### What was NOT done

The non-ident operand is still refused: `High('abc')`, `High('ab' + s)` and
`High(('ab'))` remain `High: expected array variable or ordinal type`. All three
are legal in fpc — and each has a DIFFERENT base (`High('abc')` = 2, a 0-based
array-of-char constant; `High('ab' + s)` = 5, a 1-based managed value;
`High(('ab'))` = 1, still the constant despite the parens), so widening the
guard is its own job and needs its own measured table. A loud refusal is the
right placeholder for it; this ticket's subject was the silent wrong ANSWER on
the shapes that already compile.

Test: `test/test_high_and_low_of_a_string.pas`, wired into `test-core`,
`.expected` = fpc's own output. Fourteen rows including the canonical
`for i := Low(s) to High(s)` walk, an empty string (High < Low, zero
iterations), a record field, a class field, a call result, a `const` parameter,
and the two array rows above.

Gate: `make compiler/pascal26` converged in 1 round, `tools/gate.sh quick`
GREEN, fpc-testsuite 344 pass / 1 fail / 171 skip — unmoved.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.
