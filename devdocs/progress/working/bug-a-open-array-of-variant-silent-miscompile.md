---
track: A
prio: 45
type: bug
---

# Open `array of Variant` parameter silently miscompiles (reads only first elem)

Found building `pyeval` (feature-lib-pyexec), 2026-07-21, with `compiler/pascal26`.

## Symptom

A function taking an **open** `array of Variant` and indexing it returns wrong
results — it behaves as if only element 0 is readable (Length/indexing collapse).
No error; silent wrong output.

```pascal
function sum(const a: array of Variant; n: Integer): Int64;
var i: Integer;
begin sum := 0; for i := 0 to n-1 do sum := sum + pyvar_to_int(a[i]); end;
...
SetLength(arr, 3); arr[0]:=pyvar_of_int(10); arr[1]:=pyvar_of_int(20); arr[2]:=pyvar_of_int(5);
writeln(sum(arr, 3));   { prints 10, should be 35 }
```

## Contrast — what WORKS

A **fixed**-size array of Variant passed by `var` is correct:

```pascal
type TBuf = array[0..7] of Variant;
function sum(var a: TBuf; n: Integer): Int64; ...   { returns 30 for 10+20 — OK }
```

So the defect is specific to the OPEN-array-of-Variant parameter shape (the
implicit `high`/element-stride for a 16-byte managed element), not to Variant
arrays in general. `array of Int64` open arrays are fine.

## Workaround in use

pyeval passes call args in a `TPyList` (a class = pointer) instead of an open
array — sidesteps this and needs no fix to land M1. Ticket kept so the shape gets
fixed for general Pascal code.

## Likely area

Open-array descriptor / element-stride computation when the element type is a
16-byte managed Variant — probably a stride or high-bound miscalc making every
index alias element 0.
