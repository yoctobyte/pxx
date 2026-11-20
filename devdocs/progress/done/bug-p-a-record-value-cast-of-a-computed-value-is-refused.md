---
slug: bug-p-a-record-value-cast-of-a-computed-value-is-refused
title: "`TRec(d*2)` / `TRec(f(x)).field` -- a record value cast of a non-lvalue is refused with IR_UNSUPPORTED"
track: P
type: bug
prio: 20
status: done
owner: claude-dupwt
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

## Fixed 2026-11-20 (claude-dupwt)

Two arms in IRLowerAddress (ir.inc), both reached only by shapes that did not
work before:

1. **The tail.** A computed SCALAR (integer, Boolean/Char, Single/Double) in
   an address position gets a hidden temp of its own kind: one store, then
   its address. Only nodes that fell to IR_UNSUPPORTED reach it. C is
   excluded, because `&(a+b)` is not C.
2. **AN_PTR_CAST to a scalar VALUE type over a non-lvalue**
   (`TB4(LongWord(k*256+k)).b1`). The generic AN_PTR_CAST arm takes the cast's
   value AS the address, which is right for `PFoo(x)`. For `LongWord(expr)` it
   dereferenced the number and **segfaulted, on the published compiler too**.
   It now spills the same way. A lvalue operand is still peeled by the arm
   above (FPC's variable typecast), unchanged.

test_tdoublerec_alias_cast grew the cases: `TPair(z * 2).hi`,
`TPair(Twice(z)).hi`, `TPair(q + 1).lo`, `pr := TPair(Twice(z) + 1.0)`,
`TB4(LongWord(w + 1))`, a loop over `TB4(LongWord(k*256+k)).b1`, and
`TDoubleRec(z * 0.5).SpecialType` / `TDoubleRec(-z).Sign`. Output = fpc 3.2.2
on x86-64; i386 and aarch64 match it. (fpc refuses `TB4(w + 1)` with "Illegal
type conversion: Int64 to TB4", because the sum is 8 bytes; the fixture spells
it as fpc accepts it.) Gate quick GREEN. test-core ran to its end with one red, the elf-reader
vacuity guard, which comes from 6cdc4bea7e, not this change (fixed
separately: done/bug-t-elf-reader-subject-went-16-aligned.md).
