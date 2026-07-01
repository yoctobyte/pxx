# `SizeOf` wrong for static arrays, and rejects most named types

- **Type:** bug (SizeOf / consteval — correctness) — Track A
- **Status:** backlog — **Symptom 1 fixed** (pin v131, 2026-07-01); Symptom 2
  (type-name resolution) still open, see below
- **Severity:** high — `SizeOf(arr)` silently returns the wrong number (no error),
  breaking the ubiquitous `SizeOf(buf)` (I/O length) and
  `SizeOf(arr) div SizeOf(arr[0])` (element count) idioms.
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Progress: Symptom 1 fixed (pin v131)

Root cause confirmed exactly as guessed: the `SizeOf(variable)` fallback path
(`compiler/parser.inc`, the "not a type name — accept a variable operand"
branch) read `TypeSize(Syms[sci].TypeKind)` unconditionally — but array
symbols store their *element* type in `TypeKind` (the same "array symbols
store ELEMENT type" landmine that's bitten several other places in this
codebase this session and before). Fixed by checking `Syms[sci].IsArray` and
computing `elementSize * Syms[sci].ArrLen` (`ArrLen` already holds the
flattened element count for N-D arrays too), with a `RecSize`-based path when
the element type is itself a record (array-of-record).

Regression test `test/test_sizeof_array_typename.pas` covers all rows of the
symptom-1 table (1-D, byte-element, array-of-record, N-D, plus the
already-correct record-var control case). Self-host byte-identical, full
`make test` green, `make stabilize` green.

**Not fixed, deliberately out of scope for this pass:** `SizeOf(arr) div
SizeOf(arr[0])` — the indexed-expression form `SizeOf(arr[0])` — still fails
to parse (`SizeOf`'s argument handler only recognizes a bare identifier or
type name, not an arbitrary expression); this is really Symptom 2's
"`SizeOf` should accept more than a name" gap wearing a different hat. Left
for whoever picks up Symptom 2 below.

## Symptom 1 (FIXED, kept for reference) — `SizeOf(staticArrayVar)` returned the element size, not the total

```pascal
var
  arr10: array[0..9] of integer;   { want 40 }
  bytes: array[0..15] of byte;     { want 16 }
  recs:  array[0..4] of TRec;      { TRec = 3 ints = 12; want 60 }
  m:     array[0..2,0..2] of integer;  { want 36 }
begin
  writeln(SizeOf(arr10));  { prints 4   — element size }
  writeln(SizeOf(bytes));  { prints 1   — element size }
  writeln(SizeOf(recs));   { prints 8   — neither 60 nor 12 }
  writeln(SizeOf(m));      { prints 4   — element size }
end.
```

Observed vs expected:

| Variable | expected | got |
| --- | --- | --- |
| `array[0..9] of integer` | 40 | 4 |
| `array[1..3] of integer` | 12 | 4 |
| `array[0..15] of byte` | 16 | 1 |
| `array[0..4] of TRec` (TRec=12) | 60 | 8 |
| `array[0..2,0..2] of integer` | 36 | 4 |
| `TRec` (record type, control) | 12 | 12 ✓ |

`SizeOf` of a record type/var and of scalar/pointer/enum vars is correct; only
**array** sizing is wrong — it yields the element size (1 machine word for the
record case) instead of `elementSize * elementCount`. No diagnostic is emitted,
so callers get a plausible-but-wrong length.

## Symptom 2 — `SizeOf(typeName)` rejects most named types

`SizeOf` applied to a **type name** only works for record types and builtins; a
named alias of any other kind is rejected:

```pascal
type
  TInt  = integer;                 { SizeOf(TInt)  -> error }
  TArr  = array[0..9] of integer;  { SizeOf(TArr)  -> error }
  PI    = ^integer;                { SizeOf(PI)    -> error }
  TEnum = (eA,eB,eC);              { SizeOf(TEnum) -> error }
  TSet  = set of (sA,sB);          { SizeOf(TSet)  -> error }
  TStr  = string;                  { SizeOf(TStr)  -> error }
  TRec  = record a: integer; end;  { SizeOf(TRec)  -> OK (4) }
```

```
error: SizeOf: unknown type or variable
```

`SizeOf` of a *variable* of those same types is accepted (the value is then
subject to symptom 1 for arrays). So the type-name resolution path only
recognises `record` types and builtin type names; it should accept any named
type.

## Likely cause

Two adjacent gaps in the `SizeOf` argument handler: (a) for an array operand it
reads the element type size rather than computing the aggregate
(`elemSize * Π extents`); (b) the type-name branch only matches record/builtin
type symbols instead of resolving any type symbol to its byte size. Both want the
same underlying "byte size of this type" helper that record types already use.

## Acceptance

- [x] `SizeOf(arrayVar)` yields the aggregate size; the table above matches;
      multi-dim arrays multiply all extents. **Done, pin v131.**
- [ ] `SizeOf(T)` works for every named type kind (alias, array, pointer, enum,
      set, string, record) — Symptom 2, still open.
- [ ] `SizeOf(arr) div SizeOf(arr[0])` gives the element count — needs
      `SizeOf` to accept an arbitrary expression argument (indexed
      expression), not just a bare identifier; effectively part of Symptom 2's
      "SizeOf should accept more than a name" scope.
- [x] Regression test (`test/test_sizeof_array_typename.pas`) wired into
      `make test`; self-host stays byte-identical. **Done, covers Symptom 1.**
