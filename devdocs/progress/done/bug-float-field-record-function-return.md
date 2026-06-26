# `Single` field/element inside a record or array stores/loads as zero

- **Type:** bug (codegen — 4-byte Single in an aggregate)
- **Track:** A — `compiler/**`
- **Status:** backlog
- **Opened:** 2026-06-25
- **History:** originally filed as "a function returning a record with float
  fields loses the values". The **Double** case turned out to be a different root
  cause — an integer argument to a float parameter was not converted (`V(1,1,1)`
  passed raw int bits into Double params, so the whole vector was 0). That is
  **fixed** (v64, `bug-int-arg-to-float-param` / the int→float call-arg
  conversion in `IRLowerCallArg`); all Double-field records now round-trip and the
  `Vec3` `VAdd(VScale(V(1,1,1),0.5),V(2,2,2))` chain gives `2.5`. The residual,
  below, is specific to **Single** (4-byte float) inside an aggregate.

## Symptom

A `Single` **record field** or **array element** stores/loads as 0; a plain
`Single` variable is fine.

```pascal
type S2 = record a, b: Single end;
var sv: Single; s: S2; arr: array[0..2] of Single;
begin
  sv := 3.5;     writeln(sv:0:1);      { 3.5  — OK (plain Single var) }
  s.a := 4.5;    writeln(s.a:0:1);     { 0.0  — WRONG (Single record field) }
  arr[1] := 5.5; writeln(arr[1]:0:1);  { 0.0  — WRONG (Single array element) }
end.
```

So the per-variable Single narrow path (slot store/load, param prologue) is
correct, but a Single at a 4-byte offset **inside a record or array** is not —
the field/element store/load almost certainly uses the 8-byte double path
(`movsd`/no `cvtsd2ss`) instead of the 4-byte `movss` with the proper
single↔double narrowing, so the value is mis-sized.

## Impact

Any record/array of `Single` (compact vectors/colors, vertex buffers). `Double`
aggregates work; switching a field to `Single` silently zeroes it.

## Likely area

The record-field / array-element store+load codegen for `tySingle` — mirror the
per-variable Single handling (narrow to 4 bytes on store via `cvtsd2ss` + `movss`,
widen on load via `cvtss2sd`) at the `IR_FIELD`/`IR_INDEX` access sites, on every
target (the per-variable narrow is already target-split — see
feature-single-first-class).

## Done when

- `s.a := 4.5; writeln(s.a)` and the array form give `4.5`; `record a,b,c: Single`
  round-trips through a function result too.
- Regression test under `make test`; self-host fixedpoint byte-identical.

## Resolution (2026-06-25, v66)

A `Single` field/element is a 4-byte float, but the IR value model carries floats
as **double** bits, so the raw size-based field/element store/load mishandled
them:

- **x86-64** (the reported target): `IR_STORE_MEM` stored the low dword of the
  double bits (no `cvtsd2ss`), and `IR_LOAD_MEM` read 4 single-bytes as the low
  dword of a double (no `cvtss2sd`). Fixed: narrow (cvtsd2ss) before the 4-byte
  store; load 4 bytes + widen (cvtss2sd). i386/arm32 already handled both.
- **aarch64**: the Single AND Double `IR_STORE_MEM` paths reinterpreted an
  **integer** value as float bits (`fmov`) instead of converting it (`scvtf`), so
  `s.a := 10` / `d.a := 10` into a float field/element stored ~0. Fixed: `scvtf`
  for an int value, `fmov` for an already-float value.

Verified Single + Double field/array, int and float values, and a Single-field
record function result, identical on x86-64/i386/aarch64/arm32. Regression
`test/test_single_in_aggregate.pas` in `make test`, `test-aarch64`, `test-arm32`.
Self-host byte-identical; pinned v66.
