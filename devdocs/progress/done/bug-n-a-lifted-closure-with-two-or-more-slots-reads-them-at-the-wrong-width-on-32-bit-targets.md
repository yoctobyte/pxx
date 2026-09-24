---
track: N
prio: 70
type: bug
blocked-by: []
summary: "FIXED 2026-09-24. The runtime closure bridge (PyBoundFnCallvnMaskBody, pyeval.pas) calls every lifted NilPy body with one 64-bit word per slot, while the body declares its slots at their real types (a Variant or nonlocal cell travels by a pointer-sized ADDRESS). Wherever a pointer is narrower than the word, the two disagree. Fix: on a target with TARGET_PTR_SIZE < 8, PyBoundFnEntry (pyparser.inc) gives the bridge a word thunk whose params are all Int64 and which calls the real body with each word narrowed or dereferenced to that slot's real type. A second, independent 32-bit defect surfaced on the same corpus row: an untyped parameter claimed nonlocal by an escaping def read back EMPTY, because every 32-bit backend's EmitLoadVariantAddr* took the address of the cell-POINTER symbol instead of its value. Fixed in all four (i386/arm32/xtensa verified; riscv32 applied, NilPy cannot run there). Guard: test/test_nilpy_lifted_closure_slots_on_32bit.npy, wired into test-i386 and test-arm32. Inert until the next pin."
status: done
---

# A lifted closure reads its slots at the wrong width on 32-bit targets (from 2 slots on i386/arm32, from 1 on xtensa)

## Repro (HEAD 6eaabf48c, compiler sha 4e32f1dde0ec)

```python
add2 = lambda a, b: a + b
print(add2(2, 3))
```

- **x86-64:** prints `5`.
- **i386, arm32:** SIGSEGV. The backtrace is `pyvar_callv2 → pyboundfn_callvn → PyBoundFnCallvnMaskBody → $pylam1 → pyadd_v → PyVarUserArith → PyVarUserObj`: the body's second Variant argument is garbage.

What the arity boundary looks like:

- `lambda x: x * 2`, `lambda: 42`: correct. The body has one slot, or none.
- `lambda a, b: 7`: correct. The body never reads the slots.
- `def f(a, b)` passed as a value and called: correct. It does not go through the TBF bridge.

## Mechanism

- `PXXDBG='a.ir:$pylam1' --target=i386` shows the lifted body's params `a` and `b` as `tk=22`, which is Variant, passed by address. That is a 4-byte word on i386.
- The bridge fills `p: array[0..31] of Int64` and calls `TBF2(code)(p[0], p[1])`, which passes two 8-byte words. The body reads `b` from the high half of `p[0]`.

The fix is an ABI decision, not a bridge tweak. Repacking the words in the runtime would have to follow each target's 64-bit argument alignment: arm32 AAPCS and xtensa put an Int64 in an even register pair. It would also need per-slot widths that the object does not record (`BKindMask` holds kinds, not widths).

The normalising fix is for the **lifter to declare every lifted slot as one 64-bit word** on every target, and re-type it inside the body. That makes the bridge's "one Int64 per slot" contract true everywhere, instead of only where a pointer is 8 bytes. Check the other producers of bound-fn bodies before choosing: the nested-def lifter (`pyparser.inc` ~11405, ~11876, ~12046, ~12193) and the callback bridges.

## Acceptance

- The repro above prints `5` on i386, arm32, riscv32 and xtensa (QEMU esp32s3), and `lambda x: x * 2` applied to 5 prints `10` on xtensa.
- The three corpus tests above match CPython on i386.
- A fixture with three own params plus one int capture plus one pointer capture, so that mixed widths are covered and the interesting slot is not first.

Found 2026-09-24 (frankH) by the first NilPy-corpus census on a real ESP32-S3 board.


## Resolution (2026-09-24, frankH, Track N)

**Two causes, both 32-bit-only, both invisible on x86-64/aarch64.**

1. **Slot width.** `PyBoundFnEntry(realPi)` returns `realPi` on a 64-bit target.
   Otherwise it registers `$pywordthunk_<pi>` with one `Int64` param per slot and
   queues it with `PyPendLamTok = -3`. The `bStart = -3` arm in
   PyCompileLambdaBody builds `return REAL(conv(w0), ...)`, where a by-ref or
   Variant slot becomes `deref(PVariant(wk))` through a typed pointer local, and
   anything else is the word narrowed to the slot's type. All three
   AN_PROCADDR sites use it: the lambda lifter, PyMakeBoundFnValue and
   PyNestedDefClosureValue. The thunk also sets the real lambda's Variant
   params IsRef/const itself, because the LIFO queue compiles the thunk BEFORE
   the lambda body writes those flags. Without that, the pointer was boxed into
   a fresh Variant and the lambda saw an empty value. That was the thunk's
   first draft.
   The xtensa register-pair explanation above was never confirmed by
   disassembly and did not need to be: the thunk removes the mismatch whatever
   the ABI does with it.
2. **Untyped param in a nonlocal cell** (the `shared e` row of
   nonlocal_escaping_closure). It was NOT the bridge: `c` was empty BEFORE any
   call, and even with no call (`g = [bump]`). The IR was identical to
   x86-64's, so the defect was in lowering. `EmitLoadVariantAddr386` answered
   `lea [ebp+slot]` for a `load_sym` of the POINTER-typed cell symbol, and the
   Variant copy read 16 bytes of stack. x86-64's var_store asks `IREmitNode`
   and never reaches its own twin. The boundary, measured: an `int` param
   worked, a local Variant cell worked, and only an untyped PARAM failed,
   because only that path copies `$byref.c` into a heap cell and then reads
   the cell back through the pointer symbol. Fixed by the same rule in
   EmitLoadVariantAddr{386,Arm32,RISCV32,Xtensa}: a pointer-typed symbol's
   VALUE is the slot address.

**Verified:**
- test_nilpy_lifted_closure_slots_on_32bit matches CPython on x86-64, i386,
  arm32 and xtensa (ESP32-S3 QEMU).
- The pinned compiler (4e32f1dde0ec) dies after its first row on i386.
- test_nilpy_nonlocal_escaping_closure now matches CPython on i386, arm32 and
  x86-64.
- The census rows funcvalue, lambda_container_result, sorted_key_dispatch,
  min_max_key_in_a_variable and return_nested_def pass on i386 and xtensa QEMU
  (earlier compiler 8ba23adbb458; the census was not re-run on hardware).
- gate.sh quick is GREEN.
- **riscv32 is NOT verified**: hosted NilPy cannot build there (the mmap arena
  wall).
- **Inert until the next pin.**

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 16f54d98f.
