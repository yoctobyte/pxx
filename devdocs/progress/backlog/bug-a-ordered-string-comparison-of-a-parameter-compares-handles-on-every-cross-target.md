---
track: A
prio: 70
type: bug
blocked-by: []
summary: "`L < R` on two string PARAMETERS answers from the heap HANDLES, not the content, on i386, arm32, aarch64 and riscv32. `P('b','a')` reports L<R TRUE and L>R FALSE; equal strings report L<R TRUE. `=` and `<>` are correct, and the same comparison between local or global variables is correct — it takes a parameter operand to break. Silent wrong answer on four targets."
status: backlog
owner: ""
---

# Ordered string comparison of a parameter compares handles, not content

- **Track A** (the ordered `<` `<=` `>` `>=` string-compare lowering / its
  per-target emitters).
- Found 2026-08-21 by a 53-test cross differential over the dyn-array +
  interface family. Surfaced as `test_interface_directives` printing
  `cmp -1 -1 6` instead of `cmp -1 1 6` on all four cross targets.
- **prio 70, above the family it was found in**: this is not a leak or a
  refusal, it is a wrong VALUE that no diagnostic reports. Any cross-target
  program that sorts, bisects, or orders strings is quietly wrong.

## Repro — minimal

```pascal
program cmp3;
procedure P(L, R: string);
begin
  Writeln('L<R ', L < R, '  L>R ', L > R, '  L=R ', L = R,
          '  len ', Length(L), ' ', Length(R));
end;
begin
  P('b', 'a');
end.
```

| target | output |
| --- | --- |
| x86-64 | `L<R FALSE  L>R TRUE  L=R FALSE  len 1 1` |
| i386 | `L<R TRUE   L>R FALSE  L=R FALSE  len 1 1` |
| arm32 | `L<R TRUE   L>R FALSE  L=R FALSE  len 1 1` |
| aarch64 | `L<R TRUE   L>R FALSE  L=R FALSE  len 1 1` |
| riscv32 | `L<R TRUE   L>R FALSE  L=R FALSE  len 1 1` |

`=` is right, `<>` is right, `Length` is right. Only the ORDERED operators lie,
and all four targets lie identically.

## It is the parameter, not the string

Ordered comparison between plain variables is correct on every target:

```pascal
var a, b: string;
begin a := 'a'; b := 'b';
  Writeln(a < b, b < a, a < a, a > b, b > a, a <= a, a >= a);   { all correct }
```

Mix one parameter in and it breaks:

```pascal
procedure P(L: string);
var loc: string;
begin
  loc := 'a';
  Writeln(L < loc, loc < L, loc < loc);
end;
{ P('b'):  x86-64  FALSE TRUE FALSE     aarch64  TRUE FALSE FALSE }
```

`loc < loc` is right; both comparisons involving `L` are wrong. All three
parameter modes behave the same — `L, R: string`, `const L, R: string` and
`constref L, R: string` all fail identically, so it is not a by-reference
unwrap.

## Why "handles, not content" is the reading

Equal strings answer `L < R` **TRUE**: `C('a','a')` returns -1 from an
`if L < R then -1 else if L > R then 1 else 0` ladder. A swapped-operand bug
would still answer FALSE for equal operands, so the operands are not swapped —
something that differs between two equal strings is being compared, and the only
such thing is the heap handle. That is the exact failure mode
`compiler/ir.inc` already documents for a different pair
(`bug-p-string-char-relational-compares-lengths`): `=`/`<>` have hand-emitted
forms in every backend, the four ordered operators never did, so an unrecognised
operand type falls through to the ordinary integer compare and compares
pointers.

The likely mechanism is therefore in typing, not in the compare: a string
PARAMETER's operand type is not being seen as `tyAnsiString` at the point where
the ordered path is chosen, so the node takes the integer arm. `PXXDBG` on the
IR for `P` will say which — dump it for a local pair and a parameter pair and
diff the two binop nodes' `tk`.

x86-64 is immune, which is the usual shape here: it has its own emitter for this
and never consults whatever the four share.

## Gate

The two repros above matching x86-64 on i386 / arm32 / aarch64 / riscv32;
`test_interface_directives` printing `cmp -1 1 6` / `cls -1 1 6` on all four;
the 53-test dyn-array + interface cross differential no worse than baseline;
self-host fixedpoint + `tools/gate.sh quick`.
