---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, while writing random.sample's wasm32 row)
tags: [wasm32, arc, variant, use-after-free]
summary: "On wasm32, storing an object into a Variant (IR_VAR_STORE / IR_VAR_BOX with a tyClass source) took no reference. Overwriting the Variant then released the object's only reference and freed it under its owner. `xs = [..]; v = xs; v = 1; len(xs)` read the freed block (0xDDDDDDDD under PXX_HEAP_DEBUG), and a list passed to any pylib shim or user def inside a loop was empty from the second iteration. It was a silent wrong value on the whole target. The wasm32 payload now retains unless the source owns its +1 (IRNodeOwnsManagedObj), as i386, x86-64, arm32, aarch64, riscv32 and xtensa do. Those other targets were measured correct before the fix."
owner: ""
---

# A Variant store of an object does not retain on wasm32

```python
pop = [10, 20, 30]
v = pop
v = 1
print(len(pop))      # wasm32 before: 0 (PXX_HEAP_DEBUG: -572662307), CPython 3

for i in range(3):
    random.shuffle(pop)
    print(len(pop))  # wasm32 before: 5 0 0
```

## Cause

`WasmVariantPayload` (compiler/ir_codegen_wasm32.inc) widened a class
pointer to the 8-byte payload with no retain. Every other backend's
IR_VAR_STORE class arm calls `PXXObjRetain` unless `IRNodeOwnsManagedObj`
says the source already owns its +1. A pylib function doing
`Result := someList; PXXObjRelease(someList)` also returned a freed list.

## Measured

- It is use-after-release, not only a missing retain: under
  PXX_HEAP_DEBUG the length read after `v = 1` is 0xDDDDDDDD, the fill of
  a freed block.
- Other targets, before the fix, with the shuffle-in-a-loop repro: i386,
  riscv32, arm32, aarch64, xtensa windowed and xtensa call0 all print
  5 5 5. Only wasm32 printed 5 0 0.
- Sweep: every wasm32 recipe line in the Makefile (233 lines, excluding
  shell continuations), run with the compiler before and after the fix.
  No line goes red. The ones that go green are this fix's own rows and
  rows for features the old compiler lacks.

## Fix

In `WasmVariantPayload`, a tyClass arm: emit the pointer, then
`PXXObjRetain` it unless `IRNodeOwnsManagedObj(valNode)`, then
zero-extend it into the payload. Both callers (IR_VAR_STORE, IR_VAR_BOX)
evaluate the payload before the destination address, so the scratch local
is free at that point.

## Rows

- test/test_nilpy_an_object_stored_into_a_variant_is_retained.npy, with
  .expected from CPython: global and local aliasing, and a list passed to
  shuffle, prod, fsum, choice and a user def inside for and while loops.
  Rows: wasm32 (red before the fix), x64 and i386.
- test/test_nilpy_an_object_stored_into_a_variant_is_released.npy under
  PXX_ALLOC_CENSUS on wasm32: `drop` has 26 live over 5000 stores of a
  borrowed and an owned list; `keep` is the positive control and trips
  the bound. The value is checked too (25000).
