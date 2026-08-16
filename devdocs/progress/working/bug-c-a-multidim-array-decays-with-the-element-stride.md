---
track: C
prio: 65
type: bug
blocked-by: []
summary: "Both strides of a decayed multi-dim array were wrong: `m+1` on `int m[3][4]` stepped 4 bytes instead of a 16-byte ROW, and `m[1]+1` stepped ONE byte instead of an element, so `*(m[1]+1)` answered 0x05000000 for 5. Silent in both directions."
---

# A multi-dim array decays with the wrong stride, in both shapes

- **Type:** bug (silent wrong value) — **Track C** / Track A file
  (`compiler/cparser.inc`, `compiler/ir.inc`).
- **Found:** 2026-08-16, by the gcc-differential sweep that also produced
  [[bug-c-a-string-literal-row-of-a-2d-char-array-stores-its-address]] and
  [[bug-c-a-2d-array-parameter-loses-its-row-length]].

## Measured (before)

```
(char*)(m+1) - (char*)m     gcc 16      pxx 4
*(m[1] + 1)                 gcc 5       pxx 83886080   (= 0x05000000)
```

The second one is the tell in miniature: 5 read one byte early.

## Two causes, one for each shape

- **`m + 1`** — `IRPointerStride` answered from `Syms[].ElemType`, and a
  multi-dim array's element type is its SCALAR. C decays `int[3][4]` to
  `int(*)[4]`, so the stride is the element size times the product of the
  remaining dims. Fixed there, from `SymArrNDims` / `SymArrDimSpan`.
- **`m[1] + 1`** — a partial index is built as a RAW BYTE ADD over a base
  retagged `tyInt64` (`bug-c-partial-multidim-array-index`), so neither operand
  of the outer `+` is a pointer and `IRPointerStride` fell through to its
  size-1 default. The builder is the only place that knows what the decayed
  row steps by, so it stamps it on the node — `ASTSLen` beside the element
  record `ASTSOffset` already carries for that same node shape.

## Still open, filed separately

`*m` and `*(t[1]+2)` — dereferencing a pointer whose pointee is an ARRAY. C
says that is a no-op yielding the row's address; pxx emits a LOAD, so `**m`
fails to compile and `*(*(t[1]+2)+3)` segfaults. Different root cause (the `*`
operator, not the stride): [[bug-c-deref-of-a-pointer-to-array-loads-instead-of-decaying]].

## Result

`test/carr2d_decay_stride.c` — both strides, 2-D and 3-D, a row assigned into
an `int(*)[4]` and into an `int*`, a char row, and the 1-D forms that must stay
untouched — returns 42 under both gcc and pxx.

## Gate

`make compiler/pascal26` + the test + `tools/gate.sh quick` — GREEN.
