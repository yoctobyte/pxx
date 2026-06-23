# bug: SetLength rejects an indexed array element as target

- **Type:** bug (Track A — IR codegen / type system)
- **Status:** DONE 2026-06-23 (both cases A and B fixed, all targets)
- **Found:** 2026-06-23, building the solitaire engine (array of card piles)
- **Severity:** medium (forces a different data shape for arrays-of-dynarrays)

## Update 2026-06-23 (later) — case B FIXED, all targets

Case B (`var a: array[0..3] of TA`, fixed outer / dyn-array-alias element) is now
fixed, end to end and on every target (verified x86-64 + aarch64/i386/arm32 vs
FPC). The element layout change landed:

- New `SymElemDynDepth[]` parallel array (defs.inc) — element dyn depth for a
  FIXED array whose element is itself a dynamic array; reset in every `Alloc*`.
- `LastTypeElemDynDepth` global threads the depth from the parser into
  `AllocArray`, which lays each slot out pointer-sized and stamps
  `SymElemDynDepth`. Parser detects the dyn-alias element in the fixed-array
  var-section path (per-name, re-set before each `AllocArray`).
- `NodeDynDepth` / `NodeDynBaseTk` (AN_INDEX) and the `IR_INDEX` stride/tag in
  `ir.inc` now report `a[i]` as a pointer-sized dyn-array handle, so SetLength /
  Length / indexing / whole-element assignment all route through the existing
  dyn-array machinery (no new IR op — fully target-independent).
- Proc-local fixed-array-of-dyn slots are nil'd in the prologue via a
  per-element pointer-sized zero loop (works on all targets; the multi-byte
  managed-aggregate zero path is x86-64-only), so SetLength on an element does
  not release a garbage "old" handle (this was a segfault).

Self-host byte-identical; `make test` green. Regression:
`test/test_fixed_array_of_dynarray.pas` (globals, multi-name decl, record
element, proc-local grow/shrink, repeated calls).

Residual: scope-exit release of a proc-local fixed-array-of-dyn's element
handles is not emitted (they leak at function return — no crash, correct output);
matches pxx's existing tolerance for fixed-array-of-managed locals. A separate
cleanup-pass enhancement if it ever matters.

## Update 2026-06-23 — root cause found; case A fixed

The real defect is broader than "IR codegen rejects an indexed target". The
indexed-target IR path (`ir.inc:2787`) already works; the problem is that a
**named dynamic-array type alias used as an array element loses its dynamic
dimension** during var-section parsing, so the element is never recognised as a
dyn array and `SetLength` is misrouted.

`ParseTypeKind` only knows the scalar/set/pointer alias table — array-type
aliases live in the separate `ArrType` table — so parsing `array of TA`
(`TA = array of Integer`) resolved `TA` to its bare base type (`Integer`) and
dropped the `array of`. The literal form `array of array of Integer` always
worked because the parser composes depth in its own nested-`array` loop.

**Case A — dynamic outer (`var m: array of TA`): FIXED.** The var-section
`array of` path now detects a dyn-array alias element via `FindArrayType` and
composes `dynDepth + ArrTypeDynDepth[alias]` with the alias's base element type,
before falling through to `ParseTypeKind`. Verified for scalar and record
element types; regression test `test/test_nested_dynarray_alias.pas`.
(parser.inc, var-section `array of` branch.) Self-host byte-identical.

**Case B — fixed outer (`var a: array[0..3] of TA`): STILL FAILS.** This is the
original repro below. A fixed array whose element is a dynamic array needs a
genuine layout change: each element slot must be pointer-sized (a dyn-array
handle, not the base type inline), and the symbol must carry an element
dyn-depth so `NodeDynDepth(a[i])` / `NodeDynBaseTk` report the element as a dyn
array. Touch points: `AllocArray` element size + a new `SymElemDynDepth[]`
parallel array (reset in every `Alloc*`, per the recycled-slot landmine), the
fixed-array stride/index helpers (`symtab.inc` ~2434-2519), and the `AN_INDEX`
cases of `NodeDynDepth`/`NodeDynBaseTk`/`NodeDynBaseRec` (`ir.inc:448`). Deferred
— a workaround exists (fixed 2D array + per-pile counts, the project's preferred
shape) and the change is multi-site with reseed risk.

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
