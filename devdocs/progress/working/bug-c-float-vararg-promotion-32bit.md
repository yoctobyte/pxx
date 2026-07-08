---
prio: 55
---

# C: float (single) vararg prints 0.000000 on i386/arm32/riscv32 — default argument promotion missing

- **Type:** bug (backend/call lowering — 32-bit targets). Track A.
- **Found:** 2026-07-08 by the new C cross-conformance matrix
  (feature-c-cross-target-feature-coverage): 00174 + 00175 fail identically on
  i386, arm32, riscv32; aarch64 and x86-64 pass.

## Repro
```c
float a = 12.34 + 56.78;
printf("%f\n", a);            /* 32-bit: 0.000000; expected 69.120003 */
printf("%f\n", 12.34 + 56.78); /* fine everywhere (double expr) */
```
Also any `float` PARAM forwarded to printf (00175's `floatfunc(float a)`
prints `float: 0.000000` for all inputs on the three targets).

## Symptom scope
- Double literals/exprs to varargs: correct on all targets.
- `float` variable or parameter to varargs: 0.000000 on i386/arm32/riscv32.
  C99 6.5.2.2p6 default argument promotion (float → double for `...`) is not
  applied (or applied with a wrong 4-byte slot) on the 32-bit call paths.
- x86-64 + aarch64 OK, so the shared C frontend promotes somewhere the 64-bit
  paths honor; the 32-bit variadic marshalling passes the raw single (or a
  half-filled pair) and `__pxx_va_arg` reads garbage/zero.

## Where to look
Per-target variadic call marshalling (the v178 arc:
project_cross_variadic_arm32_riscv32_v178) — check where a tySingle argument
to a variadic C call gets widened; likely needs an explicit single→double
convert before slotting on the 32-bit targets (2 words), mirroring whatever
the x86-64 path does via xmm.

## Gate
00174 + 00175 pass under `tools/run_c_conformance.sh --target {i386,arm32,riscv32}`;
drop their lines from `test/c-conformance/pxx.skip.{i386,arm32,riscv32}`;
existing variadic guards stay green; self-host byte-identical.
