# `SizeOf` wrong for static arrays, and rejects most named types

- **Type:** bug (SizeOf / consteval — correctness) — Track A
- **Status:** backlog — **Symptom 1 fixed** (pin v131, 2026-07-01); **Symptom 2
  type-name resolution fixed** (pin v134, 2026-07-01); the `SizeOf(arr[0])`
  arbitrary-expression-argument part of Symptom 2 is still open, see below
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

## Progress: Symptom 2 type-name resolution fixed (pin v134)

`SizeOf`'s type-name branch (`compiler/parser.inc`, the `sizeof` intrinsic
handler) only ever matched `record`/`class` types and hardcoded builtin
names; anything else (integer alias, named array type, pointer alias, enum,
set alias, string alias) fell through to the variable-lookup fallback and
errored. Fixed by mirroring the SAME resolution chain `ParseTypeKind`
already uses for a `var x: T` declaration:

1. `FindArrayType(name)` first (named array types are resolved outside
   `ParseTypeKind` in `ParseVarSection`, so they need the same early check
   here) — aggregate size via `elemSize * Π extents` (or `RecSize` for
   array-of-record), same formula as Symptom 1. A *dynamic* named array
   type resolves to `TARGET_PTR_SIZE` (it's a reference/handle, matching
   FPC: `SizeOf` of a dynamic-array type is the pointer width).
2. Record/class match — but ONLY if `FindTypeAlias(name) < 0`. This guard
   is load-bearing: the compiler pre-registers internal RTTI descriptor
   records under common names (`TProc`, `TParam`, ...), and `ParseTypeKind`
   already has this exact "user alias shadows builtin record" rule for
   `var` declarations. Missed this on the first pass — a hand-written test
   using `TProc = procedure(x: Integer);` (a name that collides with the
   compiler's own builtin) silently resolved to the WRONG record and
   printed `704` instead of `8`; caught by diffing against real FPC output
   before landing, not by self-host (this collision isn't exercised by the
   compiler's own source).
3. `FindTypeAlias(name)` — set/pointer/general-scalar/proc-type alias,
   `TypeSize(AliasTk)`; a `tyRecord`-shaped alias (method-pointer-of-object)
   uses `RecSize(AliasElemRec)` instead, since `TypeSize(tyRecord)` is a
   placeholder pointer-width slot, not the real size.
4. `FindEnumType(name)` — ordinal/integer-sized, matching `ParseTypeKind`'s
   own comment ("enums are ordinal/integer-sized at codegen").
5. Existing variable-operand fallback, unchanged.

Verified every case from this ticket's Symptom 2 table plus a named
array-of-record, a named dynamic-array type, a record-of-record alias, and
the `TProc`-collision case, all diffed byte-for-byte against real FPC output
(`fpc -Mobjfpc` with `{$H+}`) — including the one pre-existing, deliberate
divergence: this compiler represents EVERY set as a fixed 32-byte bitset
regardless of element-range (`TypeSize(tySet) = 32` everywhere, already true
for `SizeOf(setVariable)` before this fix too), where FPC packs small sets
tighter; not a regression, just this dialect's existing set-size model.
`test/test_sizeof_array_typename.pas` extended with 8 new cases (including
the `TProc` shadow case) instead of a new file. Self-host byte-identical,
full `make test` green.

**Still open:** `SizeOf(arr) div SizeOf(arr[0])` (an arbitrary INDEXED
EXPRESSION as the argument, not just a bare identifier/type name) — not
attempted this pass, see Acceptance below.

## Likely cause

Two adjacent gaps in the `SizeOf` argument handler: (a) for an array operand it
reads the element type size rather than computing the aggregate
(`elemSize * Π extents`); (b) the type-name branch only matches record/builtin
type symbols instead of resolving any type symbol to its byte size. Both want the
same underlying "byte size of this type" helper that record types already use.

## Acceptance

- [x] `SizeOf(arrayVar)` yields the aggregate size; the table above matches;
      multi-dim arrays multiply all extents. **Done, pin v131.**
- [x] `SizeOf(T)` works for every named type kind (alias, array, pointer, enum,
      set, string, record) — Symptom 2 type-name resolution. **Done, pin v134.**
- [ ] `SizeOf(arr) div SizeOf(arr[0])` gives the element count — needs
      `SizeOf` to accept an arbitrary expression argument (indexed
      expression), not just a bare identifier; effectively part of Symptom 2's
      "SizeOf should accept more than a name" scope. Still open.
- [x] Regression test (`test/test_sizeof_array_typename.pas`) wired into
      `make test`; self-host stays byte-identical. **Done, covers Symptoms 1 and 2.**
