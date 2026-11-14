---
track: C
tags: [C, atomics, gibux, portability, aarch64, arm32]
prio: 30
type: feature
blocked-by: []
summary: "C now has gcc's __sync_* and __atomic_* builtins (1/2/4/8 bytes, all sequentially consistent), <stdatomic.h>, the _Atomic qualifier, and the __ATOMIC_* / __GCC_HAVE_SYNC_* / __GCC_ATOMIC_*_LOCK_FREE predefines. Each builtin lowers to a per-width helper the translation unit carries itself (hosted and --freestanding), built on AN_ATOMIC. Also fixed: aarch64 IR_ATOMIC was relaxed ldxr/stxr with no barrier, so it is now ldaxr/stlxr + dmb ish; arm32 gains the leading dmb ish."
status: done
owner: unassigned
---

# C: `__sync_*` and `__atomic_*` builtins

The Gibux session asked for these on 2026-11-13 ("whenever it suits"). The
owner said on 2026-11-14: "buy portability". Gibux locks through its own x86
inline asm today. With the builtins, the kernel and third-party C can use the
portable spelling.

## How it works

- **Intrinsics** (cparser `CAtomicIntrinsic`):
  `__pxx_atomic_{xchg,cas,add}{32,64}(addr, ...)` build AN_ATOMIC, the
  same node Pascal's `__pxxatomic_*` and `InterLocked*` use. Each returns the
  old value.
- **Rename** (cparser `CAtomicRewrite`): each gcc builtin becomes
  `__pxx_a_<op>_<N>`, where N is the byte size of the first argument's
  pointee. Literal arguments carry the operation code and old-or-new
  selection. The memory-order arguments are evaluated and passed, and the
  helpers ignore them, so every operation is sequentially consistent.
- **Result type** (cparser `CAtomicRetype`): value-returning builtins come
  back in the pointee's type. Narrow integers are truncated and re-extended
  by their signedness, so `__atomic_fetch_sub(&i, 1) < 0` is a signed
  comparison. A pointer result keeps its pointee, so
  `__atomic_load_n(&head, o)->next` works.
- **Helper bodies** (cpreproc `CAddAtomicBuiltins`): C source that the
  translation unit carries itself when its text mentions `__sync_` or
  `__atomic_`. Prototypes go on line 1 and bodies at the end, the same
  mechanism as the freestanding bit builtins. There is no crtl and no header,
  so a kernel object needs nothing at link time.
  - The 4- and 8-byte helpers use the intrinsics directly: add is xadd,
    exchange is xchg, everything else is a cas loop.
  - The 1- and 2-byte helpers run a cas loop on the containing aligned
    4-byte word, so neighbouring bytes are untouched.
  - The 8-byte set is omitted on ILP32 targets, which have no 64-bit
    IR_ATOMIC. The frontend refuses an 8-byte object there by name.
- **`<stdatomic.h>`** (lib/crtl/include, header-only, used hosted and
  freestanding): typedefs, `memory_order`, the `atomic_*` macros and
  `atomic_flag`.
- **`_Atomic`**: the qualifier form is dropped by the lexer, like
  `volatile`. A plain `x++` on an `_Atomic` object is therefore not atomic
  under pxx (gcc makes it seq_cst). This is documented in the header. The
  specifier form `_Atomic(T)` is refused by name.

## Fixed along the way: aarch64 and arm32 ordering

aarch64 IR_ATOMIC was `ldxr`/`stxr` with no barrier, which is relaxed.
Pascal's `InterLocked*` and every C atomic use it, and a lock built on it does
not order the critical section on real hardware. qemu-user's TCG hid this. It
is now `ldaxr`/`stlxr` plus a trailing `dmb ish`. arm32 already had the
trailing `dmb ish`; it now has the leading one too, matching gcc's ARMv7
`__sync` sequence.

## Tests (test-core, after the caplusint rows)

- `csyncat26`, `csyncat_a64`: `test/c_sync_atomic_builtins.c`, every builtin
  at 1, 2, 4 and 8 bytes. It covers signed and unsigned values, old against
  new results, a failed cas writing back `expected`, the generic pointer
  forms, a pointer object, and byte atomics beside guard bytes. The output
  equals gcc's (`test/c_sync_atomic_builtins.expected`, 63 lines).
- `cstdatomic26`, `cstdatomic_a64`: `test/c_stdatomic.c`, equal to gcc's.
- `csyncat_a64_order`: the aarch64 binary contains the cas sequence
  `ldaxr ... stlxr ... dmb ish` three times. The frozen latest compiler emits
  the relaxed `ldxr` form.
- `csyncat_i386_8`: an 8-byte atomic on i386 is refused by name.
- `catomic_spec`: `_Atomic(int)` is refused by name.
- `c_fs_atomics`: a `--freestanding` object with no undefined symbols. A gcc
  pthread driver runs 4 threads × 20000 iterations against it, covering 8-byte
  add, a test-and-set spinlock, 2-byte cas loops on both halves of one word,
  and byte adds in one word. The totals are exact. A control with the
  increments made plain loses updates (`add 237486` of 240000).
- The Pascal parallel-writeln atomic test still passes on aarch64 and arm32.

The frozen latest compiler stops at the first builtin ("call to undeclared
function: __sync_fetch_and_add").

## Not done

- `_Atomic(T)` specifier; atomic semantics for plain operators on `_Atomic`.
- 16-byte atomics; 8-byte atomics on i386 and arm32 (cmpxchg8b /
  ldrexd).
- riscv32 and xtensa have no IR_ATOMIC
  (bug-a-riscv32-and-xtensa-have-no-atomic-codegen); the builtins refuse
  there by name.
- `__atomic_always_lock_free` is a call, not a constant expression, so it
  cannot appear in `_Static_assert` or an array size.
