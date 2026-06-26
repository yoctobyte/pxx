# bug: assigning one fixed array to another (`b := a`) does not copy

- **Type:** bug (codegen — value assignment of a static array)
- **Status:** done
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** Track B, AES-128 (`lib/rtl/aesgcm.pas`) — `tmp := s` in ShiftRows
  produced garbage; every static-array `:=` had to be replaced with an element
  loop.

## Symptom

`b := a` where `a, b` are the same fixed-array type does **not** copy `a`'s
elements into `b`. `b` is left with garbage (the copy doesn't happen at all):

```pascal
type TA = array[0..3] of Byte;
var a, b: TA; i: Integer;
begin
  for i := 0 to 3 do a[i] := i + 1;   { a = 1,2,3,4 }
  b := a;
  a[0] := 99;
  writeln(b[0]);     { prints 236 (garbage) — want 1 }
end.
```

A by-element copy (`for i := … do b[i] := a[i]`) works. So the value-copy
semantics of `:=` on a whole static array are missing/miscompiled.

## Impact / workaround

Anywhere a static array is assigned wholesale — common in crypto/state code
(`state := tmp`, `ctr := j0`, `v := y`). Workaround: copy element-by-element (or
via a small `procedure Copy(var d; const s)`). `lib/rtl/aesgcm.pas` does this
throughout — see [[track-b-workarounds]].

Note: records assign/copy fine, and dynamic arrays have their own (reference)
semantics; this is specifically **static/fixed arrays by value**.

## Acceptance

- `b := a` for a fixed-array type copies all elements (`b[0]` stays 1 after
  `a[0] := 99`), for element types of any width (Byte / Integer / Int64).
- Regression test.

## Log
- 2026-06-25 — fixed (74f4f30). Root cause: a whole fixed-array `:=` (LHS is an
  AN_IDENT array, ArrLen >= 0) had no branch in the AN_ASSIGN dispatch
  (ir.inc) — it fell through to the generic scalar store, which moves only one
  element's width. Added a whole-static-array branch emitting IR_COPY_REC over
  `ArrLen*elemSize` (same op records use; same size idiom as the static-array
  arg-copy path), gated to 1-D arrays of non-managed elements
  (Byte/Integer/Int64/record); managed-element arrays (string / managed-record
  elements) stay on the scalar path (per-element ARC, separate work). Lowered
  through shared IR so all backends inherit it. Verified x86-64 +
  aarch64/arm32/i386 (incl Int64 on 32-bit); regression test
  test/test_fixed_array_copy.pas; make test + self-host + cross-bootstrap all
  byte-identical. Track B can now drop the element-loop workaround in
  lib/rtl/aesgcm.pas.
