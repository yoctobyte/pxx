---
track: A
prio: 45
type: bug
---

# NilPy: `bytes(seq[a:b])` leaks the intermediate slice object every call

`bytes(x[a:b])` — a `bytes()`/slice where the slice result is an **unbound
intermediate** consumed by the outer call — leaks one owned object per
evaluation. The slice call (`pybytes_slice` / `pylist_slice`, pylib.pas)
returns an owned TPyBytes/TPyList (+1); as an argument to `bytes(...)` (or any
consumer) that owned temporary is never released.

## Evidence (isolated repro, mmap-arena peak RSS, 2M iters)
```python
b = bytes(mem[8:16])   # in a loop  -> 359 MB, linear ~180 B/iter  (LEAK)
s = mem[8:16]          # slice alone, bound to a local -> 264 KB flat (ok)
b = bytes(src)         # bytes() of a fixed list       -> 264 KB flat (ok)
```
Only the FUSED `bytes(slice)` leaks: the slice bound to a local is reclaimed
(local-reassign reclamation), and `bytes()` of a non-temp is fine. It is the
**unbound owned slice temporary in argument position** that is not released —
the same class as [[feature-nilpy-object-reclamation]] slice 4 (owned call
result as arg), but the existing owned-arg-release path (ir.inc ~1979, gated
`CurrentUnitIdx<0`, tyClass ctor/param arg) does not fire for a slice-call
result feeding `bytes()`/a builtin.

## Where it bites
uforth's `VM._snapshot_input_state` does three `bytes(self.memory[a:a+8])`
slices PER interpreted line (confirmed via valgrind: `PXXObjAlloc <-
pybytes_slice <- _snapshot_input_state`, definitely-lost). Linear in lines, so
a minor contributor to the core-suite RSS — but `bytes(slice)` in any hot loop
leaks unbounded.

## Fix direction
Register the owned slice-call result as a hidden owning temp released after the
consuming call (extend the owned-result-arg reclamation to slice-call results
feeding builtins/`bytes()`), or have the consumer take ownership. Track A/N
(reclamation lane). Repro compiles with any current compiler.
