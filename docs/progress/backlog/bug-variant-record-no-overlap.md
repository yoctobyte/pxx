# bug: variant record (case fields) do not share storage

- **Type:** bug (Track A — record layout) — silent wrong value
- **Status:** backlog
- **Found:** 2026-06-23, differential probe vs FPC
- **Severity:** medium (variant-record reads return 0 / garbage instead of the
  aliased bytes)
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
