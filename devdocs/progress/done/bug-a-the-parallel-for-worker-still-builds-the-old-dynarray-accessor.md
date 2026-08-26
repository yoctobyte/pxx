---
slug: bug-a-the-parallel-for-worker-still-builds-the-old-dynarray-accessor
title: "`parallel for` still built the pre-`@dy` dynamic-array accessor, and segfaulted on every target"
track: A
prio: 72
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-26
resolved: 2026-08-26
commit: PENDING-COMMIT
summary: "REGRESSION, mine, same day. bug-p-address-of-a-dynamic-array-captures-the-handle-not-the-variable changed what a pointer-to-dyn-array holds — the variable's SLOT, not the handle. Three consumers were left on the old convention: the parallel-for worker's capture accessor and both dyn-array argument arms in ir.inc. test_parallel_for_capture_aggr segfaulted on x86-64, i386, arm32 and aarch64."
---

# What broke

Before, a `^TDyn` held the array's HANDLE — `@la` and `p^[i]` both worked on the
data pointer. `bug-p-address-of-a-dynamic-array-captures-the-handle-not-the-variable`
made `@dy` yield the VARIABLE's slot, and `p^[i]` moved with it: it now uniques
through p's value as a handle SLOT address.

Three places kept building the old shape.

1. **The `parallel for` worker's capture accessor.** For a dyn-array capture it
   synthesized

   ```pascal
   capj := Pointer(PNativeInt(NativeInt(__pfctx) + off)^);   { the DATA pointer }
   ```

   so `capj^[i]` read the array's first ELEMENT as a handle. Segfault, on all
   four targets that run `parallel for`.

2. **`p^` to a var/out dyn-array parameter** (`ir.inc`). It materialised a
   hidden slot — `temp := handle; pass &temp` — to give the callee something to
   deref. With p already holding the slot address that is one indirection too
   many: the callee derefed to the slot ADDRESS and read that as the handle.

3. **`p^` to a by-value dyn-array parameter.** It passed p's value as the
   handle; p's value is now the slot, so it needs a load through it.

# Found by

The Track T watcher: `test-aarch64 / test-arm32 / test-i386 / test-threads
#src:test/test_parallel_for_capture_aggr.pas`, STILL-RED at `d3c1e87dce5b`, all
four `qemu: uncaught target signal 11`. Reproduced natively in eight lines — a
`parallel for` over a captured fixed array passes, the same loop over a captured
dynamic array segfaults.

# Fix

**One convention, applied to all three.**

* The worker now emits the SAME accessor for every capture kind —
  `capj := Pointer(NativeInt(__pfctx) +/- off)`, the address of the frame slot —
  and `capj^` reads whatever that slot holds: inline data for a scalar, fixed
  array or record, the handle for a dyn array. The special case is deleted, not
  adjusted.
* The var/out arm passes `p`'s value straight through; the hidden-slot
  materialisation is deleted.
* The by-value arm loads through it.

The two argument arms were written as mirrors of each other and the comment on
each said so; they moved together, which is what made the second one findable
from the first.

# Verification

- All twelve `test/test_parallel*.pas`: **OK**, including
  `test_parallel_for_capture_callee` — the test written FOR the old convention,
  which the hidden-slot arm existed to serve and which now passes without it.
- `capture_aggr`, `capture_callee`, `capture` and `capture_string` re-run on
  i386, arm32 and aarch64 through `tools/run_target.sh`: all OK.
- `test_pointer_to_a_dynamic_array` still matches its fpc `.expected`.
- `tools/gate.sh quick` GREEN; conformance 346 pass / 0 fail with the sets
  diffing clean; fgl 7/7; self-host converged.

# Lesson

The convention change was gated, and the gate was green, because the quick tier
does not run `--threadsafe` cross-target jobs. A change to what a POINTER MEANS
has a blast radius the size of every consumer of that pointer, and the way to
find them is to grep for the consumers, not to trust the tier that happens to
run. The comment I wrote at the `p^[i]` site even said "reachable only since
`@dy` began yielding the slot" — the right next question was "what else was".
