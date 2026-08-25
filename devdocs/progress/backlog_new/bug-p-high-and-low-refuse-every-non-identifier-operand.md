---
slug: bug-p-high-and-low-refuse-every-non-identifier-operand
title: "`High('abc')`, `High('ab' + s)` and `High(('ab'))` are all parse errors"
track: P
prio: 35
type: bug
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Both arms open with `if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type')`, so a string literal, a concat, or a parenthesised expression cannot be an operand at all. fpc takes all three — and gives each a DIFFERENT base, which is why widening the guard needs its own measured table rather than a one-line edit."
---

# Refused today, legal in fpc 3.2.2

```pascal
var s: AnsiString;
begin
  s := 'qxy';
  WriteLn(High('abc'));      { fpc: 2   pxx: High: expected array variable or ordinal type }
  WriteLn(High('ab' + s));   { fpc: 5   pxx: same error }
  WriteLn(High(('ab')));     { fpc: 1   pxx: same error }
  WriteLn(Low('abc'));       { fpc: 0   pxx: Low: expected array variable or ordinal type }
  WriteLn(Low('ab' + s));    { fpc: 1   pxx: same error }
end.
```

`compiler/pasparser_expr.inc`, both arms:

```pascal
if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type');
```

A proc NAME already escapes this (it starts with an identifier — fixed by
`compat-pascal-index-a-function-call-result`), so `High(F)` works. A literal or a
`(` does not.

# Why this is not a one-line widening — THREE bases

Measured, and this is the whole reason the ticket exists:

| operand | fpc `Low` | fpc `High` | why |
| --- | ---: | ---: | --- |
| `'abc'` | 0 | 2 | a string CONSTANT is an array-of-CHAR constant, 0-based over its own length |
| `('ab')` | 0 | 1 | …and the parens do NOT change that — so the test must ask the NODE, not the token |
| `'ab' + s` | 1 | 5 | a managed-string EXPRESSION, 1-based over its length |
| `'ab' + 'cd'` | 1 | 4 | two literals concatenated are an ANSISTRING expression, not a char array |
| `sh + 'x'` (`sh: string[10]`) | 0 | 255 | a shortstring EXPRESSION, 0-based over the DEFAULT capacity |

So "it starts with a quote" tells you nothing; the answer depends on the value's
type and on whether it is a constant. The bases themselves already exist in the
compiler after
[[bug-p-high-and-low-of-a-string-are-off-by-one]] — managed = `1 .. Length`,
frozen = `0 .. capacity`, array = own bounds. What this ticket adds is
(a) letting the operand parse, and (b) an `ASTKind[valNode] = AN_STR_LIT` arm
for the constant case, which folds to `ASTSLen[valNode] - 1` / `0` and must sit
ABOVE the frozen arm (a literal's `LastExprTk` is `tyString`, so the frozen arm
would otherwise claim it and answer 255).

Do not widen the guard to "anything": `High(3)` would then reach the runtime
`Length` tail and produce garbage where it is currently a clear error. Admit
`tkString` and `tkLParen` and keep the diagnostic for the rest.

# Sibling gap in the same arm — a frozen-string RESULT has no capacity

`High(G)` where `G: TSA` returns `string[6]` answers **1** (`Length - 1`); fpc
says 6. There is no `ProcRetStrCap` row for the frozen arm to read, and
defaulting to 255 would turn a too-SMALL bound into a too-LARGE one — a loop
reading past the end rather than stopping early — so the arm currently declines
the operand rather than guessing. Adding the capacity to the proc row is a small
Track A metadata change and would close this row; do it in the same pass if the
row is easy to add, and keep the decline if it is not.

# Gate

Track P's. Every row of both tables above in a test wired into `test-core`, each
diffed against fpc 3.2.2 — including the rows that already work, since the fix
moves them onto a different path. Grep `Length`'s arm before closing: it took
the same class of fix on 2026-08-25
([[bug-p-length-of-a-string-literal-plus-anything-does-not-parse]]) and its
literal fold is the model for the `AN_STR_LIT` arm here.
