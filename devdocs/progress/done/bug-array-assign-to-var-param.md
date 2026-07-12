---
prio: 75  # silent memory corruption; trivially reachable from idiomatic code
---

# Whole-array assignment TO a `var` array parameter segfaults

- **Type:** bug (codegen / assignment lowering) — **Track A**
- **Status:** done
- **Opened:** 2026-07-12, hit by Track B while writing `lib/rtl/p256field.pas`
  (`FeInv` does `r := acc` where `r` is a `var` param).

## Symptom

Assigning a whole static array **to a `var` parameter** writes through the wrong
address and segfaults. Reduced, no units, no unsigned types needed:

```pascal
program g;
type TI = array[0..3] of Integer;
procedure CopyIn(var r: TI; const a: TI);
var tmp: TI; i: Integer;
begin
  for i := 0 to 3 do tmp[i] := a[i] + 1;
  r := tmp;                 { <-- segfault }
end;
var x, y: TI; i: Integer;
begin
  for i := 0 to 3 do x[i] := i * 10;
  CopyIn(y, x);
  for i := 0 to 3 do Write(y[i], ' ');
  WriteLn;
end.
```

`Segmentation fault (core dumped)`. Confirmed on stable v211 and on a
freshly-built compiler, x86-64.

## What works (so the blast radius is narrow)

- `tmp := a` — copying **from** a `const`/`var` array param into a local: **OK**.
- `r[i] := ...` — element-wise writes through a `var` array param: **OK**.
- Whole-array assign between two *locals* or globals: **OK**.

So it is specifically the **destination** being a by-ref array parameter. A
`var` param holds a POINTER to the caller's array; the whole-array copy appears
to use the address of that pointer SLOT as the destination (or otherwise skips
the deref) instead of the pointer's value, so it scribbles over the frame /
wild address rather than the caller's array.

`const a: TI` as a SOURCE works, which suggests the read path derefs correctly
and only the assignment's destination path is wrong.

## Why it matters

This is silent memory corruption reachable from completely idiomatic code — the
natural way to write any `procedure Op(var result: T; const a, b: T)` numeric
kernel, which is exactly the shape fixed-size field/vector/matrix arithmetic
takes (`p256field`, and `vecmath`-style code generally). It crashes rather than
producing a wrong answer only because the bad address happens to be unmapped;
a nearer-miss address would corrupt silently.

## Acceptance

- The reduced case above prints `1 11 21 31`.
- A `var`-param whole-array assign works for element types of every width
  (Integer, Int64, UInt64) and for record element types.
- Aliasing still behaves (`Op(x, x, y)` — destination aliased with a source).
- Regression test in `test/`; self-host byte-identical; cross-targets green.
- `lib/rtl/p256field.pas` `FeInv` can go back to the idiomatic `r := acc`.

## Log
- 2026-07-12 — resolved, commit 1d53fd32.
