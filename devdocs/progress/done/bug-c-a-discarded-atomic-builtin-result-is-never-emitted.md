---
track: C
tags: [C, atomics, ir]
prio: 20
type: bug
summary: "A __pxx_atomic_* call whose result was discarded (an expression statement) lowered to an IR_ATOMIC that nothing consumed, so no code was emitted. The spinlock release `__pxx_atomic_xchg32(l, 0);` vanished and the i386 8-byte test hung on its second add, and __pxx_a_fence was a no-op on every target. Fixed in compiler/ir.inc IRDiscardValue: IR_ATOMIC joins the kinds wrapped into a temp store."
status: done
owner: unassigned
found: 2026-11-14
---

# C: a discarded atomic builtin result is never emitted

```c
__pxx_atomic_xchg32((void *)l, 0);   /* statement: value unused */
```

The C frontend lowers `__pxx_atomic_*` to AN_ATOMIC, which becomes IR_ATOMIC.
IR values are emitted when consumed. A statement-level expression goes through
IRDiscardValue, which wraps calls and a few other side-effecting kinds into a
store to a temp so they are generated. IR_ATOMIC was not on that list, so a
bare `xchg` or `add` statement produced no instruction at all. There was no
error and no warning.

## Effects before the fix

- The 8-byte ILP32 spinlock was never released. Two calls in a row hung
  (cf. repro: two `__atomic_fetch_add` on a `long long`, i386).
- `__pxx_a_fence` (the body of `__atomic_thread_fence` /
  `__sync_synchronize`) emitted nothing.
- Any user code calling `__sync_fetch_and_add(&x, 1);` as a statement went
  through a helper whose result was returned, so it worked. The bug was inside
  the helpers, where the result was dropped.

## Fix

`compiler/ir.inc` IRDiscardValue: IR_ATOMIC added to the wrapped kinds in C
mode. Covered by csyncat_i386, csyncat_arm32 and c_fs_atomics_i386, which hang
or fail without it.
