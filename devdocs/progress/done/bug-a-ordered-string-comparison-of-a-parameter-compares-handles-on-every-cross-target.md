---
track: A
prio: 70
type: bug
blocked-by: []
summary: "`a < b` on two strings answers from the heap HANDLES, not the content, on i386, arm32, aarch64 and riscv32 — every operand kind, not just parameters. The four backends special-case only `=` / `<>`, so the ordered operators fall through to the integer compare. `'zzz' < 'aaa'` answers by allocation order. Silent wrong VALUE on four targets."
status: done
owner: claude-A
---

# Ordered string comparison compares handles, not content, on every cross target

> **Title correction (same day):** the first pass framed this as parameter-specific.
> It is not — see "It is every operand kind" below. The slug is left alone; the
> defect is one arm missing from four backends, for all operands.

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

## It is every operand kind — the first reading was wrong

The initial probe compared two globals `a := 'a'; b := 'b'` and got the right
answers, which is what pointed at parameters. That probe is worthless here:
**it allocates in the same order it compares**, so a handle compare agrees with
a content compare by accident on every case it tests. Reverse the allocation
order and globals fail too:

```pascal
var x, y: string;
begin
  y := 'zzz';       { allocated FIRST -> lower handle }
  x := 'aaa';
  Writeln(x < y);   { want TRUE }
  Writeln(y < x);   { want FALSE }
```

| | x86-64 | i386 / arm32 / aarch64 / riscv32 |
| --- | --- | --- |
| `x < y` | TRUE | **FALSE** |
| `y < x` | FALSE | **TRUE** |

Exactly inverted, and inverted in the direction the HANDLES point. Globals,
locals and parameters all fail; all three parameter modes (`a: string`,
`const`, `constref`) fail identically. This is not a by-reference unwrap and not
a parameter-marshalling bug.

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

## RESOLVED 2026-08-21

One shared Pascal helper plus one arm per backend — not four hand-written
`cmpsb` loops.

**`PXXStrCmp3(lenA, srcA, lenB, srcB): Int64`** in
`compiler/builtin/builtinheap.pas`, deliberately the exact counterpart of the
`PXXStrEq` that already sat beside it: same pre-decomposed (length, data)
operand shape, so managed handles and frozen inline strings share it. Returns
-1 / 0 / +1, bytes compared UNSIGNED (matching x86-64's `repe cmpsb` + unsigned
`setcc`), shorter string first on a prefix, and a nil handle arrives as length 0
so `''` is the least element with no special case.

Each of i386, arm32, aarch64 and riscv32 then gets an ordered arm that is a
byte-for-byte clone of its OWN equality arm — same operand normalisation
(`EmitStrOperandRISCV32` / `EmitArm32StringParts` / `EmitA64StringParts` / the
i386 inline decomposition), same temporary-release bookkeeping — with only the
callee and the result tail changed. The tail is each backend's existing
"-1/0/1 -> 0/1" idiom, the one its soft-float compare already uses.

Gated exactly as x86-64 gates `EmitAnsiStrCmp3Reg`: both operands a managed or
frozen string. A Char operand never needs a case here — the AN_BINOP lowering
wraps it into a string before any backend sees it
(`bug-p-string-char-relational-compares-lengths`).

x86-64 is untouched; its inline sequence stays the oracle and the self-host
binary stays byte-identical.

### Verified against FPC, not against x86-64 alone

`test/test_string_ordering_cross.pas` (new): twelve cases including reversed
allocation order, prefixes, both empty strings, a byte above 127, and case
folding. FPC's output and pxx's agree exactly on **native and all four cross
targets**.

The reversed-allocation case is the point. The obvious probe —
`a := 'a'; b := 'b'` — allocates in the same order it compares, so a handle
compare agrees with a content compare on every case it tests. That is why this
survived: it is right by accident under the test everyone would write.

### The pre-existing test that already covered this

`test/test_string_ordering.pas` has asserted exactly these operators since
`bug-string-ordering-comparison-constant`. It is built natively only, and on the
cross targets it was failing the whole time:

| | expected | pinned, i386 | pinned, aarch64 |
| --- | --- | --- | --- |
| line 1 | `101001` | `010101` | `010101` |
| line 2 | `10` | `01` | `01` |
| line 3 | `011010` | `110010` | `110010` |
| line 5 | `110` | `001` | `110` |

All five lines match on all four targets at HEAD. Both test files are kept: the
old one is the native regression for a different defect, the new one is the
shape a handle compare gets wrong.

### Cross differential

The 53-test dyn-array + interface family, native vs each cross target, against
the previous commit's baseline: **broke 0**. `test_interface_directives` now
prints `cmp -1 1 6` / `cls -1 1 6` on all four, matching x86-64.

### Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint byte-identical).

## Log
- 2026-08-21 — resolved, commit 58bb69e0e.
