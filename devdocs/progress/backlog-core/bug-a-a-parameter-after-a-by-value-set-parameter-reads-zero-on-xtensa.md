---
slug: bug-a-a-parameter-after-a-by-value-set-parameter-reads-zero-on-xtensa
track: A
prio: 55
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (test_cross_byvalue_aggregate_params, wasm32 by-value work)
summary: "On xtensa, EVERY parameter after a by-value `set of 0..255` parameter reads 0. `procedure F(s: TS; x: Integer)` called as `F(s, 30)` gives x = 0; with two trailing ints both are 0. The set itself is correct and the same signature with the set LAST is correct, so the caller and callee disagree about how many argument words a by-value 32-byte set occupies. i386 and riscv32 pass sets by value too and both are correct, so this is xtensa's own word walk, not the shared convention. Wrong VALUES, no diagnostic, and it is invisible on x86-64/aarch64/arm32 because those pass a set param's ADDRESS."
---

# A parameter after a by-value set parameter reads zero on xtensa

## Reduced

Compared against the x86-64 build of the same source, xtensa built with
`--platform=posix --xtensa-soft-mulhigh`:

```pascal
type TS = set of 0..255;
procedure F(s: TS; x: Integer);
begin writeln(1 in s, ' ', x); end;
...
s := [1,2]; F(s, 30);
```

```
  xtensa   TRUE 0        <- x is lost
  x86-64   TRUE 30
```

The variations, all measured in one run:

| signature | xtensa |
| --- | --- |
| `F(s: TS; x: Integer)` | **`TRUE 0`** — wrong |
| `F(s: TS; x1, x2: Integer)` | **`TRUE 0 0`** — both lost |
| `F(x: Integer; s: TS)` | correct |
| `F(r: TPlain; x: Integer)` (8-byte record) | correct |
| `F(s: TS)` alone, copied to a global | correct |

So the SET's own 32 bytes arrive intact and everything after it does not. That
is a word-count disagreement about the set's slot between the caller's argument
push and the callee's parameter walk, not a value bug in either.

## Why nothing caught it

`ABIParamSlotHoldsValueAddr` puts x86-64, aarch64 and arm32 on the by-ADDRESS
row, so on those three a set param is one word and a trailing parameter cannot
be displaced. Only i386, riscv32 and xtensa pass the 32 bytes, and of those only
xtensa is wrong — which is the shape CLAUDE.md's "nothing observably differs is
a claim about ONE target" section is about, one row further out: here three
targets agree with each other and with the oracle, and the fourth does not.

## Where to look

`compiler/ir_codegen_xtensa.inc`'s parameter word walk, against
`compiler/ir_codegen.inc:1770`'s (the i386/shared one), which counts a by-value
set as `TypeSlotSize(tySet)` — 32 bytes, eight words — in the same loop that
counts a by-value record by `RecSize` and an Int64 as two. The likely defect is
xtensa counting the set as one word on one side of the call and eight on the
other.

## The test

`test/test_cross_byvalue_aggregate_params.pas` contains the row that found this
(`Mixed`, a by-value record and a by-value set among scalars, `x3` printed
after both). It is wired on i386, aarch64, arm32, riscv32 and wasm32 and
DELIBERATELY NOT on xtensa; the Makefile's xtensa recipe carries the exclusion
and this slug. Wiring it green would mean deleting the row that found the bug.
Un-exclude when this closes.
