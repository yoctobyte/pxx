---
slug: bug-p-high-and-low-of-a-string-are-off-by-one
title: "`High(s)` and `Low(s)` over a string answer 0-based bounds for a 1-BASED string"
track: P
prio: 55
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
