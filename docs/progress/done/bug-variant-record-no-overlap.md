# bug: variant record (case fields) do not share storage

- **Type:** bug (Track A — record layout) — silent wrong value
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Closed:** 2026-06-23
- **Severity:** medium (variant-record reads return 0 / garbage instead of the
  aliased bytes)

## Resolution (2026-06-23)

Front-end only (record layout in ParseTypeSection), no codegen. The record field
loop had no `case` handling — `case` and its branch fields fell to the `else
Next` skip, so the branch field names that lexed as identifiers were laid out
SEQUENTIALLY (`i` at 0, `c` at 4), not overlapped.

Added a `tkCase` branch: parses `case [tag: ] T of c1,..: (fields); ... end`,
optionally laying out the discriminant as a real tag field, then computing a
single `variantBaseOff` (the aligned current offset) at which EVERY branch's
fields start — a union. The record grows by the largest branch (`variantMax`).
Scalar, fixed-array, and record branch fields are supported.

Verified byte-identical to FPC (`{$mode objfpc}`): `r.i:=65; ord(r.c)` -> 65;
`r.w:=258; r.b` -> 2|1 (LE byte overlap); fixed-part + variant
(`x; case of 0:(a:integer) 1:(bb:array[0..3] of byte)`) -> `7 4 3 2 1`. No
variant records exist in the compiler source, so self-host is unaffected.

Out of scope (separate, pre-existing, not a regression): reading a `single`
branch field aliased over an `integer` branch yields 0.0 — a single-field
reinterpret-load quirk, independent of the (now-correct) union layout. Gate:
`make test` (self-host byte-identical) + FPC oracle. Closes
bug-variant-record-no-overlap.
- **Distinct from:** `feature-cross-float-variant` (the `Variant` *type*); this is
  the `record case ... of` variant-part field overlap.

## Symptom

Fields in different branches of a record's variant part must occupy the same
storage (a union). In pxx they do not — writing one branch and reading another
yields 0:

```pascal
type tr = record case boolean of true: (i: integer); false: (c: char); end;
var r: tr;
begin r.i := 65; writeln(ord(r.c)); end.
{ fpc: 65    pxx: 0 }
```

Byte-overlap is likewise broken:

```pascal
type tr = record case integer of 0: (w: word); 1: (b: array[0..1] of byte); end;
var r: tr;
begin r.w := 258; writeln(r.b[0], '|', r.b[1]); end.   { 258 = $0102 }
{ fpc: 2|1 (little-endian)    pxx: 0|0 }
```

## Expected

The variant part is a union: all branch fields share the same offset (the record
size is the fixed part plus the largest variant). `r.i := 65; r.c` reads byte 0
of the integer (65); `r.w := $0102; r.b` reads `[2, 1]` on little-endian.

Current behaviour suggests each branch's fields are laid out at separate
(non-overlapping) offsets.

## Repro

`tools/fpc_diff_probe.sh` (`variant-record`).
