---
summary: "b := a on a static array with managed elements copies NOTHING — every element comes out empty, silently; elementwise copy and the same array inside a record both work"
type: bug
track: A
prio: 80
owner: claude-A
---

# Whole-array assignment of a static array with managed elements silently loses the data

- **Type:** bug — Track A (codegen / managed-type assignment)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** Track B, `tools/fpc_diff_probe.sh` `str-in-array` case.

## Repro

```pascal
var a, b: array[0..2] of string;
begin
  a[0] := 'p'; a[1] := 'q'; a[2] := 'r';
  b := a;
  writeln('[', b[0], '][', b[1], '][', b[2], ']');
end.
```

    FPC:  [p][q][r]
    pxx:  [][][]

**No error, no warning.** `a` is left intact; `b` is silently all-empty.

## What works and what does not — measured

| form | result |
| --- | --- |
| `array[0..1] of string`, `b := a` | **all elements EMPTY** |
| `array[0..1] of TR` where `TR` has a string field | **`[p][]`** — first survives, second lost |
| 2-D `array[0..1,0..1] of string`, `b := a` | **all empty** |
| const-initialised `array[0..1] of string = ('p','q')`, `b := a` | **all empty** |
| same arrays, copied **elementwise** in a loop | ok |
| `array[0..1] of Integer`, `b := a` | ok |
| **a record CONTAINING an `array[0..1] of string`, `y := x`** | **ok** |
| passing the array as a value parameter | ok |

The last two are the useful ones. Wrapping the identical array in a record and
assigning the record copies it correctly, and so does parameter passing — so the
machinery for copying managed elements exists and works; only the direct
whole-array assignment statement fails to use it. That comparison is probably
the whole diagnosis.

The `array of record-with-string` row giving `[p][]` rather than `[][]` says the
failure is not a simple no-op either — something copies partially, or copies and
then releases.

## Severity

Silent data loss on an ordinary statement. `b := a` on a `array[0..N] of string`
is not an exotic construct, and the failure produces empty strings rather than a
crash, so it surfaces later and somewhere else — the expensive shape described
in the debugging playbook.

## Related but distinct

`bug-p-string-char-relational-compares-lengths` (urgent) and
`bug-a-virtual-method-int64-in-and-out-32bit` (urgent) were found in the same
sweep; neither shares a mechanism with this one.

## Resolution (2026-08-05)

The comparison in the table was indeed the whole diagnosis. `IRLowerAST`'s
AN_ASSIGN whole-static-array arm (`compiler/ir.inc`) explicitly EXCLUDED managed
element types — `ElemType <> tyAnsiString`, and `not (tyRecord and
RecordHasManagedFields)` — with the comment *"Managed-element arrays need
per-element ARC and are left to the scalar path."* The scalar path does not copy
an array at all, so the exclusion was not a fallback, it was a silent no-op.
Hence all-empty results and, worse, `a := a` destroying `a[0]`. The
`array of record-with-string` row's `[p][]` was the same statement moving one
8-byte qword.

**Fix.** New `IRManagedArrayCopy` in `compiler/ir.inc` gives a managed-element
static array the same ARC shape `IR_COPY_REC_MANAGED` gives a record: retain the
SOURCE's element handles, release the DESTINATION's old ones, then bulk-copy.
Retain-before-release is what keeps `a := a` and shared handles safe. A static
array has no `[refcount][length]` header, so the walks are over a raw buffer +
explicit count — `PXXDynArrayRetainImmediate` (already existed, header-free) and
a new mirror-image `PXXArrayReleaseImmediate` in
`compiler/builtin/builtinheap.pas`. N-D arrays are stored flat, so the flattened
`ArrLen` is the right count.

Both whole-array arms now route through it: the array VARIABLE arm and the array
FIELD arm (`y.arr := x.arr`, which had the identical hole — measured `[f0][][]`).

**Also fixed in the same statement:** `array[0..N] of string[M]` was on the
memcpy path but sized with `TypeSize`, which has no case for the frozen-string
kinds and returns its default 8 — so `d := c` copied only element 0 (`[xy][]`).
Now sized with `FrozenStrSlotSize(ElemType, SymStrCap)`. Plain `tyString`
elements stay off the path deliberately: their slot width is fixed at
DECLARATION time (`STRING_CAP+8` global vs `LOCAL_STR_CAP+8` local, see
`AllocArray`) and is not recoverable from the symbol at lowering time.

**Verified** against the FPC oracle — all seven shapes agree byte for byte:
plain string array, self-assign, assign over a non-empty destination,
`string[8]` array, array of managed record, 2-D string array, array-as-field.
Locked in as `test/test_fixed_array_copy_managed.pas` (registered in the
Makefile next to `test_fixed_array_copy`).

**ARC balance measured, not reasoned:** an elementwise copy loop and the new
`b := a` reach the identical 24.96 MB max RSS at 400 000 iterations, so the new
path adds no leak. Both leak equally because of a **pre-existing, independent**
bug found while measuring this: a local `array[0..N] of string` never releases
its elements at scope exit — merely FILLING one leaks linearly. Filed as
`bug-a-local-static-array-of-string-never-released-at-scope-exit` (measured on
both sides of this fix, identical numbers). When that lands, this path's
retain/release balances exactly as intended; no change needed here.

**Gate note:** `tools/gate.sh quick` reports the self-host step RED for this
change, but `tools/selfhost_fixedpoint.sh` (the authoritative hermetic check)
converges in 2 rounds from `pinned` and agrees with `compiler/pascal26`.
gate.sh's inline `fixedpoint()` demands convergence in ONE pass, which is the
exact mistake the Makefile's `$(COMPILER)` rule documents as wrong for a
one-generation-stale seed. Filed as `bug-t-gate-sh-fixedpoint-does-not-iterate`.
`testmgr --tier quick` is 15/15 green.

## Log
- 2026-08-05 — resolved, commit c716e49d3.
