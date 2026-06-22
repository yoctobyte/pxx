# Dynamic array as a record field is corrupted (value return + var-param assign)

- **Type:** bug (compiler) — **Track A**
- **Status:** **DONE** — fixed `39d851a`, re-pinned v36.
- **Severity:** MEDIUM — had a known workaround (module globals, as in zlib),
  but it forced non-idiomatic API design on Track B libraries.
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, building the `sat` library (wanted a `TCNF` record).

## Summary

A record containing a dynamic-array field is mishandled by codegen:

- **Returning** such a record by value yields garbage array fields.
- **Assigning** a local dynamic array into a record's array field through a
  `var` parameter, then reading it back, **segfaults**.

`lib/rtl/zlib.pas:27` already documents the limitation ("The pinned stable
compiler has trouble with dynamic arrays stored in records and with passing
dynamic arrays through several parameter layers") and works around it with module
globals — but there was no ticket. This files it.

## Minimal repro (FPC-verified correct)

```pascal
program Rec;
type TR = record n: Integer; a: array of Integer; end;
procedure Fill(var r: TR);
var loc: array of Integer; i: Integer;
begin
  SetLength(loc, 3);
  for i := 0 to 2 do loc[i] := (i+1)*10;
  r.n := 3;
  r.a := loc;            { assign local dynarray into record field (var param) }
end;
function SumR(const r: TR): Integer;
var i, s: Integer;
begin
  s := 0;
  for i := 0 to r.n - 1 do s := s + r.a[i];
  Result := s;
end;
var x: TR;
begin
  Fill(x);
  writeln('len=', Length(x.a), ' a0=', x.a[0], ' a2=', x.a[2], ' sum=', SumR(x), ' want 60');
end.
```

| compiler | result |
|----------|--------|
| FPC (`fpc -Mobjfpc`) | `len=3 a0=10 a2=30 sum=60 want 60` |
| PXX v33 (pinned) | **SIGSEGV** (`len=` then crash) |

A second symptom (record returned by value) shows up via
`function ParseDIMACS(const s): TCNF` returning a record with two dynarray
fields: the caller reads `Length(cnf.Lits)` = `2071656378828587104` (garbage).

## Likely area

Managed-field handling for records whose fields are dynamic arrays: the
array field's reference/refcount is not initialised/copied on record
assignment, `var`-param store, or by-value return. Compare with the already-fixed
managed-string record work (feature-cross-managed-aggregates) — dynamic-array
fields appear to have been missed.

## Workaround in use

`lib/rtl/sat.pas` (like `zlib`) keeps the formula + working arrays as module
globals instead of a `TCNF` record. Once this is fixed, a clean record-based
API becomes possible.

## Log
- 2026-06-22 — Filed by Track B from the sat-library build. Minimal repro +
  FPC oracle. Pre-existing (documented in zlib since that unit was written).
- 2026-06-22 — **DONE (Track A, `39d851a`, v36).** Root cause was the
  whole-dyn-array assignment lowering, not refcount init: `rec.field := dynarr`
  (a non-IDENT dyn-array LHS) fell through `AN_ASSIGN` to the generic scalar
  store, which used the element width (truncating the 8-byte handle to 4) and
  stored the source's slot *address* instead of its handle → bogus pointer →
  segfault / garbage `Length`. The IR_STORE_SYM dyn-array path (plain `b := a`)
  was correct; only the field/index lvalue path was missing. Fix: detect a
  non-IDENT dyn-array LHS via `NodeDynDepth > 0` and store the handle at pointer
  width (`ir.inc` AN_ASSIGN). Covers var-param field assign, local record field
  assign, and by-value record return with dyn-array fields (all three in the
  minimal repro now pass). Share semantics (no retain/release on the field
  store) — matches how PXX dyn-arrays already behave; a refcount refinement can
  follow if a double-free surfaces, but the corruption/crash is gone. Regression
  `test/test_dynarray_record_field.pas`. Gate: `make test` + fpc-check
  byte-identical, cross-bootstrap (i386/aarch64/arm32) byte-identical, lib-test
  green. Track B can now use record-based dyn-array APIs (drop the module-global
  workaround in zlib/sat when convenient).
