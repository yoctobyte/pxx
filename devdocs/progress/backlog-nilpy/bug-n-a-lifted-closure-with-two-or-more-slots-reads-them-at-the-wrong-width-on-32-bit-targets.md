---
track: N
prio: 60
type: bug
blocked-by: []
summary: "The runtime closure bridge (PyBoundFnCallvnMaskBody in compiler/builtin/pyeval.pas) calls every lifted NilPy body through TBFn = function(a0..: Int64), i.e. one 64-bit word per slot, but the frontend declares the lifted body's slots at their REAL types — a Variant own-param is passed by address, which is a 4-byte word on a 32-bit target. So on i386/arm32/riscv32/xtensa, as soon as a body has two or more slots (own params plus captures), slot k is read from the wrong place, and the result is a crash or a wrong value. A body with exactly one slot works by accident, because a little-endian Int64 puts the pointer in the low word. x86-64 and aarch64 cannot see it. Reached by `add2 = lambda a, b: a + b; print(add2(2, 3))`: SIGSEGV on i386 and arm32 at HEAD 6eaabf48c. Also reached by corpus tests funcvalue, nonlocal_escaping_closure and lambda_container_result, and it is why they fail on the ESP32-S3."
---

# A lifted closure with 2+ slots reads them at the wrong width on 32-bit targets

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

- The repro above prints `5` on i386, arm32, riscv32 and xtensa (QEMU esp32s3).
- The three corpus tests above match CPython on i386.
- A fixture with three own params plus one int capture plus one pointer capture, so that mixed widths are covered and the interesting slot is not first.

Found 2026-09-24 (frankH) by the first NilPy-corpus census on a real ESP32-S3 board.
