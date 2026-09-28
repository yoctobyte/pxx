---
track: A
prio: 50
type: bug
blocked-by: []
status: open
found-by: frankD (Nil Python cross-target differential, 2026-09-28: the test corpus built for i386, aarch64 and arm32 at -O2, diffed against x86-64 and CPython)
summary: "pyeval calls a compiled host method with non-variant parameters through TPFn*/TPMI_* thunks declared with Int64 arguments. On x86-64 and aarch64 that is one register per argument. On i386 and arm32 an Int64 takes two words, while an Integer, Boolean, class, AnsiString or variant-address parameter takes one, so every argument after the first lands in the wrong place. test_nilpy_pyeval_host_mixed_params segfaults on both, and test_nilpy_pyeval_host_kwargs_bind_by_name segfaults on i386 and prints empty strings on arm32."
owner: ""
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
