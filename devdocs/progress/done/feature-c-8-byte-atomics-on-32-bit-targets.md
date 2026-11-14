---
track: C
tags: [C, atomics, i386, arm32]
prio: 30
type: feature
summary: "8-byte __sync_*/__atomic_* on i386 and arm32 no longer refuse: the per-TU helper takes one of 64 address-hashed spinlocks (built on the 4-byte CAS) around a plain 64-bit read-compare-write, as libatomic does, so 8-byte operations are atomic with respect to each other. __atomic_is_lock_free(8) answers 0 there (gcc -m32: 1, via cmpxchg8b). csyncat_i386/csyncat_arm32 rows equal gcc's 64-bit output apart from that one lockfree line."
status: done
owner: unassigned
found: 2026-11-14
---

# C: 8-byte atomics on 32-bit targets

`compiler/cpreproc.inc` CAtomicWidthBodies used to leave the 8-byte helpers
out when `TARGET_PTR_SIZE < 8`. cparser refused an 8-byte object with "an
8-byte atomic needs a 64-bit target". Now the ILP32 arm emits:

- `__pxx_a_lk8(p)`: picks `lk[(p >> 3) & 63]` from a static array of 64
  unsigned ints;
- `__pxx_a_cas_8`: spins on `__pxx_atomic_cas32(l, 0, 1)`, reads the 64-bit
  value, stores `d` if it equals `e`, and releases with
  `__pxx_atomic_xchg32(l, 0)` (a full barrier on both targets).

The other 8-byte operations are CAS loops over that core, as on the 64-bit
targets. The refusal in cparser is gone.

## Caveat

The lock is advisory. An 8-byte object that one thread changes through the
builtins while another writes it with a plain store, or through `cmpxchg8b` in
hand-written asm, is not protected. gcc -m32 would be lock-free there. A
lock-free version needs a 64-bit IR_ATOMIC (cmpxchg8b / ldrexd+strexd), which
is a backend job.

## Tests

- `csyncat_i386`, `csyncat_arm32`: test/c_sync_atomic_builtins.c equals its
  .expected with `lockfree 1 1` -> `lockfree 1 0`.
- `c_fs_atomics_i386`: --freestanding emit-obj, gcc -m32 -pthread driver,
  4 threads x 20000 on the 8-byte counters.

The contention test found bug-c-a-discarded-atomic-builtin-result-is-never-emitted.
