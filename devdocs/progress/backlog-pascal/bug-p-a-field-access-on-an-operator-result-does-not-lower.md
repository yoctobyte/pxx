---
track: P
prio: 30
type: bug
blocked-by: []
summary: "`(x + y).v` — a field read directly off an overloaded operator's RESULT — fails with `IR_UNSUPPORTED: frontend could not lower AST node (kind 5)`, while the same value through a temporary (`z := x + y; z.v`) is correct. Not a diagnostic difference: fpc 3.2.2 compiles the expression and prints the right number, so this is a refusal on code someone meant to write, and the workaround is invisible until you hit it. Measured identically on the PINNED binary (v40x) and at HEAD, so it is old and not a regression. AN_FIELD over an AN_BINOP whose operands are records is the shape; the operator CALL itself lowers fine everywhere else."
status: backlog
owner: unassigned
---

# A field access on an operator result does not lower

- **Found:** 2026-09-06 (frankS), incidentally, while adding Pascal `**`. It is
  NOT a `**` bug — the first probe used `**` and the second used `+`, and both
  fail the same way.
- **Measured** at compiler `113cec9cadf1` and on `stable_linux_amd64/default/pinned`.

```pascal
{$mode objfpc}
type TFoo = record v: LongInt; end;
operator + (a, b: TFoo) r: TFoo;
begin r.v := a.v + b.v; end;
var x, y: TFoo;
begin
  x.v := 4; y.v := 5;
  WriteLn((x + y).v);      { pxx: IR_UNSUPPORTED ... (kind 5);  fpc: 9 }
end.
```

Kind 5 is `AN_BINOP` (defs.inc:501), so it is the BINOP that fails to lower,
reached through the `AN_FIELD` base rather than as a statement's value. The same
operator call is fine everywhere else — through a temporary, as a `WriteLn`
argument, compared, assigned.

## Why it is worth more than a workaround

The two spellings are the same expression and only one compiles, with no
diagnostic that says so — the message names an internal node kind. A reader hits
it, adds the temporary, and never learns there was a rule. That is the shape
this repo files rather than absorbs.

## Not established

Whether every aggregate-returning operator has it, or only records; whether
`AN_INDEX` over an operator result (`(a + b)[0]`) is the same arm. Both are one
probe each and neither was run — the finding came out of unrelated work and is
banked rather than chased.
