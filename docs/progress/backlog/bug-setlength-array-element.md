# bug: SetLength rejects an indexed array element as target

- **Type:** bug (Track A — IR codegen)
- **Status:** backlog
- **Found:** 2026-06-23, building the solitaire engine (array of card piles)
- **Severity:** medium (forces a different data shape for arrays-of-dynarrays)

## Symptom

`SetLength` on an element of an array (the target is an indexed expression, not
a plain variable) fails at codegen:

```pascal
program t;
type TA = array of Integer;
var a: array[0..3] of TA;
begin
  SetLength(a[0], 5);     { error: SetLength expects an array variable in IR codegen }
  a[0][0] := 7;
  writeln(a[0][0]);
end.
```

Control — SetLength on a plain dynamic-array variable works:

```pascal
var b: TA;
SetLength(b, 5);  b[0] := 7;  writeln(b[0]);   { prints 7 }
```

## Expected

`SetLength(a[i], n)` should resize the dynamic array stored at `a[i]`. The IR
codegen needs to accept an l-value array element (indexed access), not only a
bare variable, as the SetLength target.

## Notes

- Hit while modelling 13 card piles as `array[0..12] of TCardArray`. Worked
  around by using a fixed 2D array + per-pile counts (also the project's
  preferred shape), so the engine does not need this — but the limitation is
  real and should be fixed.
- Likely the same l-value-target gap would affect other intrinsics that write
  through an indexed array element.
