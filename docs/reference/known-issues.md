---
title: Known issues in beta 0.1
order: 94
---

# Known issues in beta 0.1

These are the problems we know about in the beta 0.1 compiler, **pin v424**
(commit `0a3a7b5b4`, compiler sha256 `93a336a7ba85…`). Every row was re-run on
v424 on 2026-09-25 before it was listed here; rows that no longer reproduced
were dropped. Pascal and C rows were run on x86-64 Linux, and ESP rows under
Espressif's QEMU on both chips. A row that is fixed in the development tree but
not yet in a pin says so, with a workaround for v424.

Problems that **compile and silently give a wrong answer** come first, because a
refusal at least tells you something is wrong.

## Silently wrong

### Pascal: a record named like a compiler-internal type gets the wrong layout

```pascal
type TProc = record A: array[0..99] of Int64; end;
```

`SizeOf(TProc)` is 1344 instead of 800, with no diagnostic. Fourteen names do
this, `TProc` and `TSymbol` among them.
**Workaround:** rename the type.

### C: `long double` is 8 bytes

GCC's `long double` is 16 bytes on x86-64; PXX's is 8, the same as `double`. A
single program is consistent with itself, but a struct that contains one has a
different size from GCC's: `struct { char c; long double y; }` is 16 bytes here
and 32 under GCC. That matters as soon as such a struct crosses into
GCC-compiled code or into a file format.

### C: an initialised `__thread` variable reads 0 in other threads

`__thread int tl = 7;` reads 7 in `main` and 0 in a thread started with
`pthread_create`. **Workaround:** assign the value at the start of each thread.

### ESP: an uncaught exception does not report itself

On a desktop target an unhandled exception prints a message and the program
exits. On the ESP32-C3 the chip reboots and runs the program again, in a loop.
On the ESP32-S3 the program stops after its last output line, with no message.
**Workaround:** catch exceptions at the top level of the program.

### ESP: `Trunc` of an out-of-range float into a 32-bit integer wraps

`Trunc(1e30)` stored in a `LongInt` gives -1. The same value stored in an
`Int64` saturates to 9223372036854775807. Only the 32-bit case is inconsistent;
see [by design](#by-design-math-errors) for why ESP does not stop on a math
error at all.

## Fixed after v424

These are wrong in v424 and fixed in the development tree, so the next pin will
carry the fixes. Until then, use the workaround.

- **libc `printf` output is lost.** A Pascal program that calls libc's `printf`
  through a `varargs` external prints nothing, because the program does not exit
  through libc and libc never flushes its buffer. **Workaround:** call
  `fflush(nil)` before the program ends.
- **`writeln` of a function result leaks.** `writeln(F(k))` where `F` returns a
  string leaks one string per call: 190 of 200 were never freed in a loop.
  **Workaround:** assign the result to a local first (`s := F(k); writeln(s)`),
  which frees everything.

These are two leak rows that were measured and fixed. We are not claiming that
PXX has no other leaks of this kind: a wider check of dynamic-array shapes is
still in progress.

## Refused, with a message

These do not compile, or compile with a warning. None of them produces a wrong
answer silently.

- **Pascal `threadvar` on i386** is refused: only x86-64, aarch64 and arm32
  provide per-thread storage.
- **C `__thread` on i386 and riscv32** compiles with a warning that every thread
  shares one copy. Single-threaded programs are unaffected.
- **C `setvbuf` with full or line buffering** returns nonzero: PXX's C streams
  are unbuffered, and the call says so rather than claiming success.
- **`--shared` on aarch64 and arm32** is refused, as shared-library output is
  x86-64 only. The message reads like an internal error (`no init/fini thunk
  prologue`); on i386 the same refusal is worded plainly.

## By design: math errors

An embedded device should keep running when a sensor produces a value that
causes a math error. A desktop program should stop and say what happened. So
the two behave differently on purpose:

| | Desktop (Linux, all CPUs) | ESP32-S3 and ESP32-C3 |
| --- | --- | --- |
| Pascal and C: integer `div` / `mod` by zero | runtime error 200, the program stops | gives 0, the program continues |
| Pascal and C: float division by zero | Inf or NaN | Inf or NaN |
| Nil Python: `//` and `%` by zero | `ZeroDivisionError`, except in some shapes that stop with runtime error 200 (see the [Nil Python limits](../targets/nil-python.md#known-limits)) | gives 0, the program continues |
| Nil Python: float `/` by zero | `ZeroDivisionError`, as in CPython | Inf |

Each cell was measured on v424. The ESP column was measured under QEMU on both
chips for Pascal and Nil Python, and on the S3 for C. This
is not a bug to be fixed: if you need a zero divisor to stop an ESP program,
test the divisor yourself.

## Nil Python

Nil Python is Python-ish at best. It compiles Python-shaped source ahead of
time and is not CPython: it does not aim for parity, and it is known to have
plenty of issues. Its measured list of limits is kept on the
[Nil Python page](../targets/nil-python.md#known-limits), and the deliberate
differences from CPython are recorded beside it. On ESP, the model is
MicroPython's assumptions about a small device, such as math errors not halting
the program, not MicroPython's API.

## Reporting a problem

See [Reporting bugs](../release-notes/#reporting-bugs). A program that compiles
and gives a wrong answer is the most useful report you can send.
