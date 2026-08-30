---
slug: bug-a-xtensa-cannot-build-a-program-over-512-kib-of-code-call0-has-no-veneer
track: A+S
prio: 45
type: bug
blocked-by: []
status: backlog
summary: "`CALL0`/`CALL8` encode an 18-bit WORD offset, so a call can reach at most +-512 KiB. Nothing emits a veneer, so once the image passes that, EVERY sufficiently distant call is a hard compile error: `call0 displacement -131454 is outside the encodable range`. Five test programs hit it the moment the xtensa syscall table let them reach codegen at all. This is not an edge case — 512 KiB is a SMALL image here: test_overflow_qplus_narrow is 758 KiB of code on riscv32."
owner: unassigned
---

# xtensa cannot build a program over ~512 KiB of code

## Symptom

```
error: target xtensa: call0 displacement -131454 is outside the encodable range
       -131072..131071; the code is too large for this branch form
```

on `lib_bignum_ops`, `test_ctor_string_literal_arg`, `test_overflow_checks_qplus`,
`test_overflow_qplus_narrow`, `test_variant_comparison_coerces_a_stringy_operand`.

The diagnostic is **correct and well built** — it says exactly what happened and
why, which is [[bug-a-xtensa-pc-relative-encoders-silently-truncate-an-out-of-range-offset]]
paying off; before that ticket this truncated silently and produced a wrong PC
three functions from the cause. Nothing about the message needs changing. What
is missing is the thing that stops it from being reached.

## Why this is not a corner case

`CALL0 target` encodes `imm18` in **words**: reach is `align4(PC) + 4 +
imm18*4`, i.e. ±512 KiB. `xtensaenc.inc` checks that range correctly (it
divides by 4 before the bounds test) and errors out. There is no veneer, no
trampoline, no fallback to the long form.

512 KiB sounds generous and is not. Measured on the same sources, same tree:

| program | x86-64 code | riscv32 code | xtensa |
| --- | --- | --- | --- |
| `test_cross_float_const` | — | — | 405 KiB (builds, just under) |
| `test_overflow_qplus_narrow` | 296 KiB | **758 KiB** | refuses |

riscv32 is over the xtensa limit already and survives only because `jal` reaches
±1 MiB — it is one 1.1 MiB program away from the same wall. So this is a
**ceiling on the whole corpus**, not a property of five unusual tests: xtensa
gets 405 KiB of headroom on a hosted program before it stops compiling at all.

## The fix

xtensa has the long-call form: materialise the target with `l32r` from the
literal pool and `callx0`. Two ways to spend it:

1. **Veneers, on demand.** Keep `call0` and, when the check would fail, emit an
   island (`l32r a8, <lit>; callx0 a8`) within range and retarget. This is what
   arm32/aarch64 linkers do; it costs nothing on programs that fit.
2. **A long-call mode**, e.g. `--xtensa-long-calls`, making every call indirect.
   Simple, uniformly slower and larger — a fallback, not a default.

(1) is the right default. (2) is a cheap unblock if (1) is too big for a session.
Whichever lands, the windowed ABI needs the same treatment for `CALL8`, whose
encoding and reach are identical.

Note the register: a veneer must not clobber a live argument register. Call0
passes args in a2..a7 and a15 is the frame pointer, so a8..a11 are the safe
scratch (they are caller-saved and not argument registers in Call0).

## Provenance

Found by [[feature-s-the-xtensa-row-of-the-posix-syscall-table]]. Those five
programs previously failed in semantic analysis on `undefined variable
(SYS_openat)` and never reached codegen; supplying the table did not create this
defect, it made it reachable. Fifth instance this session of *a missing thing
hides every bug in the programs it stops from compiling*.
