---
track: A
prio: 55
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "Runtime bridges that call a compiled method through an Int64-returning thunk (pyeval host calls, pylib user-object dunders) boxed the whole Int64, but a Boolean or Integer callee sets only its own width, and on a 32-bit target nothing sets the high word (r1 on arm32, edx on i386). open-world dispatch answered True for a method that computed False (i386 always, arm32 once softfloat changed r1), a -> bool host method returned True, and len() of an array.array read 68719476739 for 3."
owner: ""
---

# A host method's result is read past its width on 32-bit targets

Rows affected, all same after the fix:

- `test_nilpy_open_world_method_dispatch`: `cross True True` on i386 (it always
  was), and `mixed True True` on arm32 once the softfloat pull changed what the
  float compare left in r1.
- `test_nilpy_pyeval_host_arity_and_returns` on arm32: `rising(3, 2, 1)` came
  back True.
- `test_nilpy_len_of_a_variant_shim_object` on arm32: `68719476739`
  (`0x10_0000_0003`) for 3, and the truth test read that as True.

## Mechanism

`TPFn*`, `TPMI_*`, `TIFn*`, `TNoArgI`, `TVarArgI` and `TStrArgI` are all
declared to return Int64, whatever the callee really returns. On x86-64 the
callee writes the full register. On 32-bit the second word is whatever the
callee last left in r1 or edx.

## Fix

`PyNarrowRet(v, rk)` in `pylib.pas` narrows a result to its RetKind:

- a byte for Boolean and Char;
- a sign-extended word for Integer;
- on CPU32, the low word for pointer, class and NativeInt kinds.

It is applied at every Int64-thunk result: pyeval's register, mixed and
`TIFn` families, and pylib's `PyUserObjNoArgMeth`, `vi` and `gi` arms.

## Test

Rows in `test-i386` and `test-arm32` for the three tests above. All three are
wrong with v446 on arm32 (open-world also on i386).
