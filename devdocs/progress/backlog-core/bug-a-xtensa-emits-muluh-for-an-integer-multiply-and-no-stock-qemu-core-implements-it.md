---
slug: bug-a-xtensa-emits-muluh-for-an-integer-multiply-and-no-stock-qemu-core-implements-it
track: A+S
type: bug
prio: 40
status: open
owner: ""
created: 2026-09-23
found-by: frank (adding the xtensa arm to the signal tests)
blocked-by: []
summary: "ANY integer multiply in a hosted xtensa program dies with SIGILL on stock qemu-user, so `--target=xtensa --platform=posix` cannot run a program that multiplies -- which includes anything that PRINTS A NUMBER, because integer-to-decimal multiplies. The backend emits `muluh` (MUL32_HIGH) and NO core model in stock qemu-xtensa implements it: dc232b, dc233c, de212, de233_fpu, dsp3400, lx106 and sample_controller all SIGILL identically, so this is not a -cpu selection fix. The faulting instruction is the one AFTER `mull`, which decodes fine -- MUL32 is present and MUL32_HIGH is a separate option -- and the emitted sequence `mull a8,a4,a2 / muluh a9,a4,a2 / mull a10,a4,a3 / mull a11,a5,a2` is a 64x64 expansion for two 32-bit Integer operands, so the high word is being computed for a multiply whose declared result is 32 bits. TWO SEPARATE QUESTIONS AND THEY HAVE DIFFERENT OWNERS: whether a 32-bit multiply should reach MUL32_HIGH at all (Track A, and it may be deliberate if Int64 is the native integer evaluation width -- do NOT assume it is a defect), and that hosted xtensa has no runnable multiply on this box either way (Track S/T, a test-infrastructure wall). NOT A SILICON BUG AS FAR AS MEASURED: ESP32 LX6/LX7 have MUL32_HIGH and the ESP profile runs under Espressif's qemu-system-xtensa, so the ESP rows are unaffected -- which is exactly why this stayed invisible. THE CONDITION THAT WOULD RETIRE IT: a hosted xtensa program that multiplies and runs to completion under a stock qemu-xtensa core, or a decision that hosted xtensa is not a supported run profile and the `--platform=posix` xtensa rows are build-only by design."
---

# xtensa emits `muluh` for an integer multiply, and no stock qemu core implements it

Found 2026-09-23 while adding the xtensa arm to the signal tests for
[[bug-a-xtensa-tkill-syscall-number-is-unlocated]]. That ticket is closed — the
syscall number was the whole of it — and this is the **residual**, recorded so
"the tests still do not run" has an owner rather than sitting in a resolution
nobody re-reads.

## Reproduction — three lines, no signals involved

```pascal
program m;
var i, q: Integer;
begin i := 7; q := i * 3; WriteLn(Chr(48 + q)); end.
```

```
$ pascal26 --target=xtensa --platform=posix m.pas m && qemu-xtensa m
qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

## What works and what does not, which is what names the instruction

| operation | xtensa/posix | riscv32/posix |
| --- | --- | --- |
| `WriteLn('hello')`, `WriteLn('a')` | **ok** | ok |
| `i shr 1` | **ok** | ok |
| `i div 10`, `i mod 10` | **ok** | ok |
| `i * 3` | **SIGILL** | ok |
| `WriteLn(i)` for `Integer` or `Int64` | **SIGILL** | ok |

**Division and modulo work and multiplication does not**, which is the opposite
of the guess anyone would make (xtensa DIV32 is also optional), and it is what
points at the instruction rather than at the operation class.

## The faulting instruction is the one AFTER `mull`

`qemu-xtensa -d in_asm`:

```
0x0804eb59:  mull	a8, a4, a2
0x0804eb5c:  ???
qemu: uncaught target signal 4 (Illegal instruction)
```

`mull` **decodes**, so MUL32 is present in the core. The undecodable instruction
is at +3. Bytes read out of the image at that offset:

```
20 84 82   mull  a8, a4, a2
20 94 a2   <- faults
30 a4 82
20 b5 82
```

`20 94 a2` is xtensa RRR with `op0=0, op1=2, op2=10, r=9, s=4, t=2` — **`muluh`**,
the unsigned-multiply-high of the **MUL32_HIGH** option, which is a *separate*
configuration option from MUL32. That is why `mull` is fine and this is not.

**No stock core model implements it.** Measured, all seven that
`qemu-xtensa -cpu help` offers, plus the default:

```
dc232b dc233c de212 de233_fpu dsp3400 lx106 sample_controller (default)
```

every one SIGILLs on the same program. **So this is not a `-cpu` fix**, and a
ticket proposing one has not measured it.

## The sequence says the operands are being treated as 64-bit

`mull a8,a4,a2 / muluh a9,a4,a2 / mull a10,a4,a3 / mull a11,a5,a2` — four
multiplies and a high word is a **64x64 expansion**, and both operands here are
declared `Integer`. So the high word is computed for a multiply whose declared
result is 32 bits.

**DO NOT FILE THAT HALF AS A DEFECT WITHOUT DECIDING IT.** CLAUDE.md records
that the native *float* evaluation type is `Double` and that evaluating wider
than the declared type is *the architecture, not a defect* — the same may be
true of integers, in which case the 64-bit expansion is correct and the only
bug is reaching an optional instruction. **The test is the same one that rule
gives: store the result in its DECLARED type and compare THAT.** If a 32-bit
product is correct, the widening is latitude.

What is NOT latitude either way: reaching an **optional ISA feature** for a
multiply. `muluh` needs MUL32_HIGH, and a target this backend supports may be
configured without it — so a narrower lowering (or a runtime/soft fallback) is
wanted on portability grounds regardless of how the width question is decided.

## Why it stayed invisible, and the scope of that

**ESP32 LX6/LX7 have MUL32_HIGH**, and the ESP profile does not run under stock
qemu-user at all — `tools/esp_run.sh` selects Espressif's
`qemu-system-xtensa` (`~/.espressif/tools/qemu-xtensa/*/qemu/bin/`) for
`-M esp32s3`. So every xtensa row the suite actually executes goes through an
emulator whose core has the option, and the hosted profile is the only one that
can see this.

This is the house pattern from CLAUDE.md — *"a whole defect class is
structurally invisible to the instrument that would normally catch it"* — with
the axis being **which emulator**, not which host word size. **Before ranking an
xtensa result, say which qemu ran it**: stock `qemu-xtensa` (user-mode, no
MUL32_HIGH) and Espressif `qemu-system-xtensa` (`-M esp32s3`) are different
instruments and they disagree on this program.

## Consequence to record, because it is bigger than one test

`--target=xtensa --platform=posix` **cannot run a program that prints a
number.** Integer-to-decimal conversion multiplies, so the wall is not limited
to source that contains a `*`. Any hosted-xtensa assertion built on printed
output is unreachable today, which is a plausible reason the hosted xtensa
corpus is as thin as it is — *that last clause is a hypothesis and is not
measured here; do not quote it as a cause.*

Three tests are in exactly this position as of this ticket:
`test_signal_num.pas`, `test_signal_siginfo.pas`, `test_signal_bss_alias.pas`
now **build** for xtensa and print a prefix (`usr1=`, `segv code=`, `hit=`)
before dying — so the signal is delivered and the handler runs, and the SIGILL
is downstream of everything they were written to test. **They are deliberately
NOT wired into the suite for xtensa**; wiring them would add three red rows for
a reason that has nothing to do with signals.

## Positive control for whoever fixes this

`i * 3` with `Integer` operands must run to completion under **stock**
`qemu-xtensa` with no `-cpu` argument. Assert the VALUE, not just the exit
status — a lowering that avoids `muluh` by computing the wrong product would
pass an exit-code row. And re-run the three signal tests above: they are the
population that wants this, and each prints a number.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
