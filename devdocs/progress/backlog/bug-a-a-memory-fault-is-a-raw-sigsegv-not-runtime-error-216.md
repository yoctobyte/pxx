---
track: A
prio: 45
type: bug
blocked-by: []
summary: "Every memory fault — nil read, nil write, a call through a nil procvar, a method on a nil object, a wild array store — kills a pxx binary with a bare `Segmentation fault` and exit 139. FPC prints `Runtime error 216` and exits 216. No message, no line, no exit-code convention, and `try..except` cannot see it."
status: backlog
owner: unassigned
---

# A memory fault dies silently, where FPC reports runtime error 216

- **Track A** (the signal runtime in `ir_codegen.inc`; entry-stub install list).
- Found 2026-08-20 by an FPC differential probe over runtime-error behaviour.

## Measured

Same source, `fpc -O- -Mobjfpc` vs pxx at `27232bed4`:

| program | FPC | pxx |
| --- | --- | --- |
| `p := nil; writeln(p^)` | `Runtime error 216`, exit **216** | *(nothing)*, exit **139** |
| `p := nil; p^ := 1` | 216 | 139 |
| nil procedure variable, called | 216 | 139 |
| virtual method on a nil object | 216 | 139 |
| `a[1000000] := 5` on `array[0..3]` | 216 | 139 |
| `Int64 div 0` | `Runtime error 200`, exit 200 | **`Runtime error 200 (division by zero)`, exit 200** |

Division by zero is exactly right — pxx even prints a better message. Every
MEMORY fault is the gap, and it is the most common runtime fault there is.

`try..except` cannot help either: FPC catches these as `EAccessViolation`, pxx
takes the signal and the process is gone, so the `except` block and everything
after it never run.

## Cause

The signal runtime is present and default-on for the PC targets
(`EmitSignalRuntimeForTarget`, `--no-signals` opts out). It installs the
dispatch handler for **SIGINT(2) and SIGTERM(15) only**; SIGSEGV and SIGBUS are
never installed, so the kernel default disposition applies and the process dies
with no message.

Everything the fix needs already exists:

- `EmitFpcFloatErrStub` is the exact pattern — an ordinary parameterless signal
  hook that reads the parked `si_code` out of `BSS_SIG_CODE` and turns a
  hardware trap into an FPC-numbered runtime error with pure syscalls, no unit
  dependency. It is installed for SIGFPE under `--fpc-float-errors`.
- `EmitDiv0Stub` is the message-and-exit shape: `InternStr` the text, `sys_write`
  it, `exit_group(200)`.
- Dispatch already parks `si_addr` in `BSS_SIG_ADDR`, so the faulting ADDRESS is
  available if the message should carry it.

So tier 1 is a fault stub modelled on those two, plus SIGSEGV/SIGBUS in the
entry stub's install list.

## Two tiers, and the second is much bigger

1. **Report and die** — `Runtime error 216` to the output, `exit_group(216)`.
   Matches FPC's exit code and first line; leaves `try..except` blind. Small,
   and it is what turns "Segmentation fault" into something a user can act on.
2. **Raise a catchable `EAccessViolation`** — FPC does this. It means unwinding
   out of signal context into the exception machinery, and every trap-to-raise
   path has to agree with `PXXDivZero`'s existing raise-hook upgrade. Its own
   sitting.

Do tier 1 first; it is most of the user-visible value.

## Open question — DEFAULT-ON or a flag? (Track U)

The signal runtime is default-on ("predictable process behavior beats size
sniffing"), which argues for default-on here. But the closest precedent argues
the other way: FPC-style **float** runtime errors are opt-in behind
`--fpc-float-errors`. Installing SIGSEGV by default changes the death of every
pxx binary — exit 216 instead of 139, and no core dump unless the handler is
declined — so it is a decision, not a detail. Filed alongside as
`decide-segv-runtime-error-default`.

## Per-arch scope

x86-64 first. The other signal runtimes (aarch64, arm32, i386, riscv32) have
their own emitters and their own frame-shape constraints — the SA_SIGINFO note
in `EmitSignalRuntime` explains why i386/arm32 cannot simply copy the x86-64
install flags. Stage them, and say in the ticket which are done, rather than
half-implementing all five.

## Gate

`make compiler/pascal26` + self-host fixedpoint, `tools/gate.sh quick`, and a
test asserting exit code 216 and the message for each of the five fault shapes
above (a `.expected` cannot carry an exit code, so assert it in the Makefile
recipe like the other `!`-guarded rows do).
