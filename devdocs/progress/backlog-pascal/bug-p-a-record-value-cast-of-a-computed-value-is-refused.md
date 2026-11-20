---
slug: bug-p-a-record-value-cast-of-a-computed-value-is-refused
title: "`TRec(d*2)` / `TRec(f(x)).field` -- a record value cast of a non-lvalue is refused with IR_UNSUPPORTED"
track: P
type: bug
prio: 20
status: open
owner: ""
found-by: claude-dupwt
created: 2026-11-20
---

```pascal
type TR = record lo, hi: LongWord; end;
var d: Double;
begin d := 1.5; writeln(TR(d*2).hi); end.
```

pxx: `error: IR_UNSUPPORTED: frontend could not lower AST node (kind 5)`.
fpc: 1074266112.

The value-cast path (pasparser_expr.inc, the record-name cast) builds
AN_DEREF(AN_ADDR(operand)), and AN_ADDR of an rvalue cannot be lowered. That
was so for the `.field` form already. Since feature-b-rtl-has-no-tdoublerec it
is also so for the bare form, which before that read a record from the address
the value's bits spelled and segfaulted. So this is a refusal, not a
miscompile. The fix is to spill a non-lvalue operand into a temp of the
record's size and take the temp's address.
