---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
commit: 3b980e9f0
summary: "`type TFD = array[0..1] of TRow; var f: TFD;` then `SetLength(f[0], 1)` was refused with `SetLength expects an array variable in IR codegen`, while the identical INLINE declaration compiled — the array-type table had no ArrTypeElemDynDepth, so the named spelling lost the element's dyn depth. Passing either spelling to an open array then copied only half the slots, because the copy-in sized elements by the ROW's base type."
---

# A named `array[0..1] of TRow` type loses its element's dyn depth

Found 2026-08-22 while fixing
`bug-p-open-array-of-a-named-dynamic-array-reads-garbage`. Pre-existing —
reproduced on `stable_linux_amd64/default/pinned`.

## The measurement

```pascal
type TRow = array of Integer;
     TFD  = array[0..1] of TRow;
var f: TFD;                       { the NAMED spelling }
var g: array[0..1] of TRow;       { the INLINE spelling — same type }
```

| | fpc | pxx before |
| --- | --- | --- |
| `SetLength(g[0], 1)` (inline) | ok | ok |
| `SetLength(f[0], 1)` (named) | ok | **`SetLength expects an array variable in IR codegen`** |
| `ByOpen(g)` → `Length(m[1])` | `1` | **`0`** (and on `pinned`, a segfault) |
| `ByOpen(f)` → `Length(m[1])` | `1` | **`0`** |

One type, two spellings, and only one of them worked — the shape
`normalise-dont-special-case.md` is written about.

## Root cause — two, one per half of the trip

**The declaration.** `ParseDeclTypeDesc` sets `VDElemDynDepth` when it parses an
INLINE fixed array whose element resolves to a dyn-array alias, and `AllocArray`
threads that into `SymElemDynDepth` — which is what the whole "each slot is a
pointer-sized handle" machinery in `ir.inc` / `ast_arena.inc` keys on. The
**named-type** branch copies `ArrTypeElemTk`, `ArrTypeElemRec`,
`ArrTypeElemRowLen/Lo`, the dims and the OUTER dyn depth, but there was no
`ArrTypeElemDynDepth` to copy: `ParseTypeSection`'s fixed-array registration had
an arm for a named FIXED element and fell through to `ParseTypeKind` for a
dynamic one, which resolves `TRow` to its base scalar. So the var's slots were
laid out as 4-byte Integers.

**The call.** Independently, the static-array→open-array copy-in sized elements
with `TypeSize(Syms[arg].ElemType)` — the ROW's base type, 4 — so a 2-element
array copied 8 bytes instead of 16 and the callee read a nil handle for `m[1]`.
This one bit the inline spelling too, which is why `g` was wrong as well.

## The fix

- `ArrTypeElemDynDepth` in `defs.inc`, stamped by `ParseTypeSection`'s new
  `ArrTypeIsDyn[fAi]` arm and read by the var-declaration named-type branch
  (into the same `VDElemDynDepth` the inline path already used) and by the
  parameter path in `pasparser_proc.inc`.
- Both open-array copy-in sites in `ir.inc` (the const/value path and the
  var path) use `TARGET_PTR_SIZE` when `SymElemDynDepth > 0`.

## Verified against fpc

Named and inline spellings of the same type asserted side by side; `SetLength`,
`Length`, `High` and indexing on each; the named type as a parameter and as an
open-array argument; regrowing a row after it was read; a managed (`string`)
element base type; and a non-zero low bound (`array[1..3] of TRow`) on the outer
array. Output byte-identical to `fpc -Mobjfpc -O1`.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_named_fixed_array_of_a_dynamic_array.pas`, 25 assertions, wired
into `test-core`.
