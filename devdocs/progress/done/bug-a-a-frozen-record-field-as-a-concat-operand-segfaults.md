---
slug: bug-a-a-frozen-record-field-as-a-concat-operand-segfaults
title: "A frozen record field as a concat operand segfaults under the byte-prefix mode"
track: A
prio: 80
type: bug
status: done
owner: "frankB"
created: 2026-09-03
summary: Under -dPXX_SHORTSTRING, `u := s + r.f` on a `string[10]` record field segfaults
  on every target, while the same field reads, assigns and compares correctly in the
  same program and the same concat over a plain variable is fine.
---

# A frozen record field as a concat operand segfaults

## Repro

```pascal
program fc;
type R = record f: string[10]; end;
var r: R; s, u: string[10];
begin
  r.f := 'FLD'; s := 'ab';
  WriteLn('read  [', r.f, '] ', Length(r.f));   { correct }
  u := s + r.f;                                  { SIGSEGV }
end.
```

`read` prints `[FLD] 3`, so the field itself is fine; only the concat dies.
A plain variable in the identical concat is correct.

## Cause — a normalisation that is free for one node type and lossy for another

`pasparser_expr.inc` retags every frozen concat OPERAND to tyString
(`ASTTk[left] := StrValTk(...)`) so that `P + '!'` on a frozen string stops
falling into pointer arithmetic
(`bug-p-a-frozen-string-concat-operand-becomes-pointer-arithmetic`). For an
`AN_IDENT` that costs nothing: the value's kind goes generic, but
`IRFrozenKindOfAddr` walks back to the SYMBOL for the width.

**A FIELD has no symbol to walk back to.** Its own IR tag WAS the width, and
the retag overwrites it with the generic tyString, which means an 8-byte
prefix — so the concat reads a byte-prefixed operand as a wide word.

**The array sibling already defends itself and the field arm did not.** The
`AN_INDEX` arm in `IRLowerAddress` takes the element kind from the ARRAY when
it is frozen and disagrees with `ASTTk`
(`bug-a-an-array-of-shortstrings-is-corrupt-under-the-byte-prefix-mode`), and
**its own comment says "Same shape as the FIELD case one arm below"** — the
field arm one arm below trusted `ASTTk` unconditionally. A comment asserting a
sibling that was never written.

## Fix

`compiler/ir.inc`, the `AN_FIELD` arm: take the kind from `RecFieldType` when
it is a frozen string and disagrees with `ASTTk[node]`, mirroring the array
arm exactly. Narrowed to frozen strings and to a disagreement, so `ASTTk` stays
authoritative for everything else.

Fixed at the aggregate rather than by narrowing the retag, for the same reason
the array arm was: the record records the kind, so lowering can always recover
it, and any future consumer that flattens `ASTTk` inherits the repair instead
of rediscovering this.

## Verification

Rows `fieldr`, `fieldl`, `fieldm` and `elemc` added to
`test/test_shortstring_concat.pas`, wired four ways. Positive control: with the
fix reverted the two `-dPXX_SHORTSTRING` modes SIGSEGV at exactly the `fieldr`
row (11 of 17 rows printed) and the two default-prefix modes are unchanged at
17 rows. x86-64, i386, arm32, aarch64 and riscv32 all produce byte-identical
output in both modes — the arm is in `ir.inc`, so all seven backends inherit it.

## NOT this

`bug-a-a-frozen-record-field-is-refused-by-overload-resolution-against-an-ansistring-parameter`
is a separate, compile-time defect on the same shape; this one is a runtime
crash and is independent (measured: the repro above segfaults with that fix
absent from the tree).

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
