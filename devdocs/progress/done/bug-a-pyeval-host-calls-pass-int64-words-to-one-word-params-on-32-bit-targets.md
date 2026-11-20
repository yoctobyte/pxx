---
track: A
prio: 50
type: bug
blocked-by: []
status: done
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "FIXED 2026-11-20: a word family (args as machine words in declaration order, Int64 and Double two words, i386 hi-first) on i386/arm32/riscv32; both refusal faces gone there. pyeval calls a compiled host method with non-variant parameters through TPFn*/TPMI_* thunks declared with Int64 arguments. On x86-64 and aarch64 that is one register per argument. On i386 and arm32 an Int64 takes two words, while an Integer, Boolean, class, AnsiString or variant-address parameter takes one, so every argument after the first lands in the wrong place. test_nilpy_pyeval_host_mixed_params segfaults on both, and test_nilpy_pyeval_host_kwargs_bind_by_name segfaults on i386 and prints empty strings on arm32."
owner: claude-dupwt
---

# pyeval host calls pass Int64 words to one-word params on 32-bit targets

Rows, all `same` on x86-64 and aarch64:

| test | i386 | arm32 |
| --- | --- | --- |
| `test_nilpy_pyeval_host_mixed_params` | rc=139 | SIGSEGV |
| `test_nilpy_pyeval_host_kwargs_bind_by_name` | rc=139 | `chars=` (empty) |

## Mechanism

`PyHostCall` in `pyeval.pas`: the "pointer family" (`TPFn*`, `TPVFn*`, `TPSFn*`)
and the mixed family (`TPMI_*` and friends) declare every non-double argument as
`Int64`. That matches the SysV x86-64 and AAPCS64 register files, where
everything is one register. On i386 (stack) and arm32 (r0 to r3, then the
stack, with Int64 pairs aligned to even registers), an Int64 argument takes two
words. The callee declares `Integer`, `Boolean`, a class, an `AnsiString` or a
`const Variant` (an address), each one word.

## Direction

On `CPU32`, the thunk argument type for a one-word kind must be `NativeInt`,
and a kind-13 (Int64) parameter still needs two words. A mixed signature needs
per-position widths, so it is either a family of thunk types keyed on a width
mask, or a small assembly trampoline per target. Refusing, with a named message,
any 32-bit signature containing kind 13 is an acceptable first step, since the
Nil Python annotation `int` is what produces kind 13.

Not fixed in the differential run. The Int64 RESULT half of this ABI is fixed
(bug-a-a-host-method-result-is-read-past-its-width-on-32-bit-targets).

## FIXED 2026-11-20 (claude-dupwt): the word family, on i386, arm32 and riscv32

Not a thunk per type sequence: a **word array**. Measured first, with a probe that
calls the same Pascal callees through all-`NativeInt` thunks laid out several
ways. pxx's own convention on all three 32-bit targets:

- every parameter is consecutive machine words in **declaration order**: one per
  pointer-sized kind, two per Int64 AND per **Double**. There is no separate
  float file and no even-pair padding (arm32 does NOT follow AAPCS here);
- the two halves of an 8-byte value go lo-first on arm32 and riscv32 and
  **hi-first on i386**, because i386 pushes left to right;
- the thunk must have **exactly** the callee's word count. On i386, and on arm32
  past r0-r3, the callee addresses its parameters from the far end, so trailing
  filler words shifted every argument (that was the first probe's failure).

`PyHostCall` now builds the words from pa[]/pd[] in declaration order and calls
through `TPW{I,V,S,D}_0..10` (5 parameters x 2 words), under `PY_HOST_WORDS`
(CPUI386 / CPUARM / CPURISCV32). Because doubles are words too, this removes
**both** refusal faces on those targets, the width face and the order face (a
double before a non-double). Both refusals are now unreachable there. They
stay for xtensa and wasm32, which were not measured. 64-bit is untouched.

Verified:

- `test_nilpy_pyeval_host_mixed_params`, `..._kwargs_bind_by_name` and
  `..._arity_and_returns` are `same` on x86-64, i386, arm32 and riscv32.
- A/B (old vs new pyeval.pas) over every NilPy test using exec/eval with an
  .expected, on x86-64, i386, arm32 and riscv32: 9 rows went DIFF -> same
  (those two plus `test_nilpy_a_builtin_method_is_a_value` on all three), 0
  went worse, and all 48 now pass.
- `test_nilpy_reflected_host_call_shapes`: a new third mode, `words`, where
  every row is a VALUE. The order probe decides it and the width probe must
  agree. Two rows were added: `mx` (eight words, a double in the middle, past
  arm32's registers) and `half` (a Double result). Pinned in the Makefile:
  i386/arm32/riscv32 = words, aarch64 = wide, and native = wide. CPython also
  reports `words`, with 0 failures.
- gate quick GREEN.
