---
track: A
prio: 35
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "FIXED 2026-11-20: not arm32 -- a Pascal PROCEDURE taken as a value got no argument-converting wrapper (the gate required IsFunc), so its raw address was called with a Variant ADDRESS where the Double belongs; x86-64 silently did not sleep, arm32 slept ~forever. Original: On arm32, `from time import sleep as sf; sf(0.0)` (or `sf(0)`) never returns, while `from time import sleep; sleep(0)` returns at once. aarch64 and i386 are fine. It is the same with v446 and fad87004e4e8. Found as the TIMEOUT of test_nilpy_an_if_decided_at_compile_time_skips_its_dead_arms on arm32."
owner: claude-dupwt
---

# arm32: a from-import alias of time.sleep hangs

```python
from time import sleep as sf
print("a")
sf(0.0)          # arm32: never returns (timeout, rc=124)
print("b")
```

`from time import sleep` followed by `sleep(0)`, `sleep(0.0)` or `sleep(1)`
works on arm32. The alias is the boundary. `time.sleep` is
`procedure sleep(seconds: Double)` in `lib/rtl/mimic_time.pas`, so the suspect
is how the aliased call hands its Double argument over on arm32 (d0 versus
r0:r1), giving the callee a huge duration.

Found by the 2026-09-28 differential: it is why
`test_nilpy_an_if_decided_at_compile_time_skips_its_dead_arms` times out on
arm32.

## FIXED 2026-11-20 (claude-dupwt): every target, not arm32

The diagnosis above was half right. The Double was garbage, but this was never
an arm32 ABI matter.  makes `g` a callable value
(pybound_new_sig), and the dispatcher calls it through the Variant convention:
each argument is passed as a Variant ADDRESS. A Pascal FUNCTION gets a
synthesized `$pycallwrap_N` that converts; the gate in PyMakeFuncValueFor
required `Procs[pi].IsFunc`, so a PROCEDURE was boxed as its raw address.
`procedure sleep(seconds: Double)` then read its Double from whatever the
dispatcher left. **On x86-64 `sf(1.5)` returned at once** (xmm0 held
something <= 0, so sleep's early exit fired): silent, measured 0.0 s against
CPython's 1.5. On arm32 the Double arrives in r0:r1, r0 being the pointer, so it
asks for ~10^9 s: the hang.

Fix (compiler/pyparser.inc): the gate admits procedures, and
PyCompileLambdaBody's bStart = -1 tail evaluates a procedure call as the
wrapper's statement, so the wrapper answers None, as CPython's sleep() does.

Verified:
- test_nilpy_a_pascal_procedure_taken_as_a_value_converts_its_arguments (new,
  in test-nilpy): `sf(0.2)` returns None after >= 0.15 s, `nap = time.sleep`
  likewise, and sf(0)/sf(0.0) return at once. It matches CPython and is
  `same` on x86-64, i386, arm32 and riscv32 (aarch64 also measured right).
  The previous latest gives `None False / False`.
- test_nilpy_an_if_decided_at_compile_time_skips_its_dead_arms is `same` on
  all four targets.
- Full test-nilpy: 0 failures. gate quick GREEN. Rebased onto rd7's
  a8d693749b (a procedure CALL in value position is None), whose row also
  stays green.
