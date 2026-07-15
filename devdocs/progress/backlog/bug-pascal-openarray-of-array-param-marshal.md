---
summary: "open-array parameter whose ELEMENT is a static array is marshalled wrong: Length(a) is huge, a[i] yields addresses/garbage — silent"
type: bug
prio: 55
---

# open array of static-array elements: call-site marshaling broken

- **Type:** bug (silent wrong values, param ABI). **Track A**.
- **Opened:** 2026-07-15 night, isolated from tforin14's residual — NOT a
  for-in bug: direct indexing shows it.

## Repro

```pascal
type T = array[1..3] of Integer;
procedure P(a: array of T);
var r: T;
begin
  writeln(Length(a));   { expect 2; pxx: ~1000+ }
  r := a[1];
  writeln(r[1]);        { expect 3; pxx: an address }
end;
var g0, g1: T;
begin
  g0[1] := 1; g1[1] := 3;  { ... }
  P([g0, g1]);
end.
```

Scalar open arrays are fine; the aggregate-element case mis-builds the
(pointer, length) pair at the call site (or indexes with base-element
stride). Check the open-array literal construction for aggregate elements
AND the callee's Length/stride metadata for array-typed elements.

## Recon (2026-07-15 night, parked)

- Call site: `[g0, g1]` parses via ParseArrayCtorAST -> AN_ARRAY_CTOR with
  elemTk = the PARAM's TypeKind, which for `array of T` (T a static array
  type) is the BASE SCALAR (tyInteger) — the lowering (ir.inc AN_ARRAY_CTOR)
  builds a dyn-array temp with AllocDynArray('', vrElemTk, 1) = 4-byte
  stride, 2 elements, and element-assigns each ARRAY through a scalar
  AN_INDEX. Three layers to fix:
  1. Param metadata: TParam needs the element's ARRAY shape (count/size) for
     `array of <static array type>` — check what the callee's decl records.
  2. Ctor: aggregate elements need row-sized SetLength stride and row-copy
     assigns (the whole-array assign path exists — see for-in N-D fix).
  3. Callee: Length(openarr)/indexing must use the aggregate element size.
- ParamIsOpenArrayScalar gates `[..]` parsing — verify it still fires for
  array-typed elements (it keys on TypeKind <> tyRecord, so tyInteger base
  passes it today, which is how the wrong path is reached).

## Recon 2 (2026-07-15, agent-A — root confirmed, feature-sized)

Confirmed this is NOT open-array-param-specific: a plain `d: array of T` (T a
static-array type) in main body already mis-indexes. `Length(d)` is now correct
(2), but `d[i]` yields addresses/garbage — the dynarray uses a SCALAR element
stride (base-type size, e.g. 4) instead of the element ROW size (e.g. 12).

Root: `parser.inc` dynamic `array of <element>` parse (~15680–15713) handles a
named DYN-array-alias element (`array of TA`, TA dyn) but has NO case for a named
FIXED-array element (`array of T`, T = `array[1..3] of Integer`) — the element
collapses to its base scalar via ParseTypeKind, dropping T's dimension. This is
the exact mirror of the handled FIXED-outer case at ~15732 ("Without this
ParseTypeKind drops TG's dimension and the element stride collapses to the base
type's size"). The inline form `array of array[1..N] of Integer` is *explicitly
rejected* (parser.inc:15690 "mixed static/dynamic nested arrays not supported"),
so aggregate-element dynamic arrays are currently an UNSUPPORTED FEATURE, not a
small metadata miss.

A proper fix is multi-layer and cross-sensitive:
1. Decl: record the element's fixed-array shape (row byte-size + inner dims) on
   the dynarray symbol so index/SetLength/copy can size a row.
2. SetLength: allocate count × rowSize (not count × baseSize).
3. Index `d[i]`: stride = rowSize; return the row as an aggregate lvalue so
   `d[i][j]` sub-indexes and `r := d[i]` row-copies.
4. Open-array param marshalling: element = row.
5. Cross backends (shared dyn-array header layout).

Parked as feature-sized. tforin14.pp depends on this (its residual after the
tforin25 fix). Byte-identical parity for both awaits this feature.

## Acceptance

- Repro prints 2 / 3; tforin14.pp goes byte-identical to FPC and both it and
  the direct-index shape get a regression test.
- Cross parity (the open-array header layout is shared).
