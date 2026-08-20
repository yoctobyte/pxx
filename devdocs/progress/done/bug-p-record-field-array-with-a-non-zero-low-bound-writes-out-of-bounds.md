---
track: P
prio: 75
type: bug
blocked-by: []
summary: "A 1-D static array FIELD of a record or class indexed from the RAW index — its low bound was never recorded, so `array[1..3]` wrote one element past its extent into the next field, `array[5..7]` wrote off the record (SIGSEGV), and `array[-2..2]` wrote into a class instance's header so Free crashed. Reads shifted with the writes, so the field looked self-consistent."
status: done
owner: frank1-ACP
---

# `r.c[i]` on a field `array[1..3]` addresses one element past the field

- **Track P** (Pascal frontend: field metadata in `parser.inc`, the index
  lowering in `ir.inc`, plus one new accessor in `symtab.inc`).
- Found 2026-08-20 by an FPC differential probe, chasing a `string[7]` record
  field that printed six characters — the neighbouring `array[-1..1]` field was
  eating its last byte. **Pre-existing**; the pinned binary does the same.

## Repro (values are `fpc -O- -Mobjfpc`'s)

```pascal
type TR = record g1: Byte; c: array[1..3] of Byte; g2: Byte; end;
var r: TR; i: Integer;
begin
  r.g1 := 200; r.g2 := 201;
  for i := 1 to 3 do r.c[i] := 10 + i;
  writeln(r.c[1], r.c[2], r.c[3], ' guards ', r.g1, ' ', r.g2);
end.
```

| | FPC | pxx |
| --- | --- | --- |
| `array[1..3]`, guards | 11 12 13, 200 201 | 11 12 13, **200 13** |
| raw memory across the record | 200 11 12 13 201 | **200 0 11 12 13** |
| `array[5..7]` | 25 26 27, 100 101 | **SIGSEGV** |
| `array[-2..2]`, guards | 8..12, 200 201 | 8..12, **9 201** |
| class field `array[-2..2]` | fine, Free returns | corrupts the instance, **Free SIGSEGVs** |
| `array[-1..1, -2..0]` (2-D) | correct | correct |
| `array[0..2]` | correct | correct |

`SizeOf` is right in every case, so the LAYOUT was never the problem — the
index arithmetic was.

## Mechanism — one arm of a double case

`IRLowerAddress`'s AN_INDEX path reads the array's low bound out of
`Syms[base].ConstVal` **only when the base is an AN_IDENT**. For an AN_FIELD
base it left `lo` at 0 — and the comment sitting on the field range-check a few
lines above says why nobody noticed: *"the parser already normalised the index
to 0-based"*. Nothing normalised it. It could not have: a 1-D array field's low
bound was never stored anywhere. `UFldArrDimLo` is filled only under
`if fNDims >= 2`, which is exactly why the 2-D row of the table above is the one
that works.

Reads and writes shifted identically, so the field itself is self-consistent and
only its NEIGHBOURS are wrong. That is how this survived a corpus full of
`array[1..N]` record fields.

## Fix

- `parser.inc` (both field-declaration sites): a 1-D static array field records
  its low bound in dim 0 of the same table. `UFldArrNDims` stays 0, so nothing
  that dispatches on the N-D shape changes.
- `symtab.inc`: `RecFieldArrLo(rec, field)` reads it back (0 for dynamic, N-D,
  or non-array fields).
- `ir.inc`: the AN_INDEX path sets `lo` from it when the base is an AN_FIELD, so
  the existing IR_INDEX `lo` operand — the same mechanism symbol arrays have
  always used — does the subtraction.
- `ir.inc`: the `{$R+}` field range check now tests `[lo, lo+count-1]` instead of
  `[0, count-1]`, and its comment no longer claims a normalisation that never
  happened.

## Verification

`test/test_record_field_array_low_bound.pas`: 53 assertions, every value FPC's
own — guards on both sides of each array, the array's own values, raw memory
across the record, constant and variable indices, a named array type, the 2-D
arm that was already right, the `low = 0` arm that must stay right, and a class
instance freed at the end. Under the pinned binary it fails and then SIGSEGVs at
`Free`; after the fix, 53/53.

Nineteen existing tests that use `array[1..N]` (range checks, cross-target,
typed consts, for-in bounds, param low bounds) were run individually and match
their recorded expectations.

## Log
- 2026-08-20 — resolved, commit 6fa645073.
