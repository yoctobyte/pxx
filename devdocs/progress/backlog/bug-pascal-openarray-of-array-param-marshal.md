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

## Acceptance

- Repro prints 2 / 3; tforin14.pp goes byte-identical to FPC and both it and
  the direct-index shape get a regression test.
- Cross parity (the open-array header layout is shared).
