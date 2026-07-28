---
track: A
prio: 85
type: bug
---

# The pxx allocator corrupts after a NilPy dict literal + repeated class allocation

Silent, and reachable from ordinary code. Repro, whole file:

```python
import json
d = {"a": 1}                  # a NilPy dict LITERAL — never used again
s = '{"a": 1}'
print(json.loads(s)["a"])     # 1
print(json.loads(s)["a"])     # CRASH ("Unhandled exception")
```

Remove the dict literal and both parses succeed. Keep it and the SECOND parse
dies — the first is fine, so it is state left behind rather than a bad parse.

**It is the allocator.** The same program compiled with `-dPXX_LIBC_HEAP`
prints `1 1` and exits clean. That is the same discriminator as
[[bug-c-unit-crashes-when-sysutils-is-used]], which also passes under the libc
heap, so the two are probably one bug.

`json.loads` here allocates a TJSONValue tree (Pascal classes) and converts it
into TPyDict/TPyList (pylib classes). The dict literal allocates a TPyDict up
front. So the shape is: allocate a pylib container, then allocate and free a
mixed set of class instances twice. Nothing in the Python source is unusual —
this is what any program that reads a settings file does.

## Why it matters now

It is what stops songformatter's session file from round-tripping:
`json.dump(...)` then `json.load(...)` in one run raises KeyError on a key that
IS in the file (the file on disk is correct — `cat` it). The `json` surface
itself is right: every operation is correct in a program that does one of them.

## Gate

`make test-nilpy` plus the repro above as a `.npy`, diffed against CPython —
and the same program under `-dPXX_LIBC_HEAP`, which must agree. Worth running
under valgrind with the pxx heap to name the offending block.

## Root cause (2026-07-28)

Not the allocator. A **double finalize** of every explicitly-`Free`d class
instance in a NilPy compilation.

The `.Free` desugar's FreeMem tail lowered to two calls (`ir.inc`, the
`-Ord(tkFreeMem)` arm):

1. `PXXClassFinalize(inst)` — emitted inline, releases the instance's managed
   fields by its runtime layout descriptor;
2. `PXXObjFree(inst)` — which for a PXXObjAlloc-headered instance calls
   `PXXObjRelease`, and at rc=0 runs the finalize hook `PyObjFinalize`, whose
   user-class arm calls `PXXClassFinalize` **again**.

So every managed field was released twice. `lib/rtl/json.pas`'s `JSONParse`
does `rd.FSrc := src` (+1 on the caller's string) and `rd.Free`; the second
finalize dropped a reference the caller still owned. The module-global `s`
reached rc 0 while still bound, its block went back on the free bin, and the
next allocation handed the same block out — the "corruption" was the allocator
correctly reusing memory the program had wrongly released.

Measured: rc history of the source string was `1` (literal) → `2`
(`rd.FSrc := src`) → `1` → `0`, one retain against two releases, the second
release arriving through `PXXObjFree → PXXObjRelease → PyObjFinalize →
PXXClassFinalize`. `-dPXX_LIBC_HEAP` hid it because glibc does not hand the
block straight back.

The inline call was wrong for a second reason: it cannot see the refcount, so
it finalized instances that were still referenced elsewhere.

## Fix

One destruction, one finalize:

- `compiler/ir.inc` — emit the inline `PXXClassFinalize` only when `not isNilPy`.
- `compiler/builtin/builtinheap.pas` — `PXXObjFree` now owns finalization for
  both populations: headered → `PXXObjRelease` alone (finalizes at rc=0, and
  not before); plain GetMem → `PXXClassFinalize` then `PXXFree`, the old order.

Regression test `test/test_nilpy_json_reparse_heap.npy` (registered in
`test-nilpy`), diffed against CPython.

## Log
- 2026-07-28 — resolved, commit HEAD.
