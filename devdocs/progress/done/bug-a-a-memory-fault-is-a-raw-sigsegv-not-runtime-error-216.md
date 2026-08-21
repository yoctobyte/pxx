---
track: A
prio: 45
type: bug
blocked-by: []
summary: "Every memory fault — nil read, nil write, a call through a nil procvar, a method on a nil object, a wild array store — kills a pxx binary with a bare `Segmentation fault` and exit 139. FPC prints `Runtime error 216` and exits 216. No message, no line, no exit-code convention, and `try..except` cannot see it."
status: done
owner: claude-A
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

## Resolution — tier 1, opt-in (2026-08-21)

All five fault shapes in the table now report FPC's number and exit code, behind
the new `--fpc-mem-errors`:

| program | before | after (`--fpc-mem-errors`) |
| --- | --- | --- |
| `p := nil; writeln(p^)` | *(nothing)*, exit 139 | `Runtime error 216 (access violation: address not mapped)`, exit **216** |
| `p := nil; p^ := 1` | exit 139 | 216 |
| nil procedure variable, called | exit 139 | 216 |
| virtual method on a nil object | exit 139 | 216 |
| `a[wild] := 5` on `array[0..3]` | exit 139 | 216 |

Without the flag every one of them still dies on 139, unchanged.

### Opt-in, because the default is not mine to pick

The ticket's own open question — default-on or a flag — is
[[decide-segv-runtime-error-default]] and is unresolved. So this ships as
`--fpc-mem-errors`, the exact shape of the closest precedent
(`--fpc-float-errors`), and the decision stays a one-line change to the default
whenever the user makes it. Nothing about the flag's existence pre-empts it.

The Makefile row asserts **both** directions — 216 with the flag, 139 without —
precisely so that flipping the default later is a deliberate act that shows up
as a failing row rather than a silent behaviour change.

### What it is built from

Nothing new, as the ticket predicted. `EmitFpcMemErrStub` is
`EmitFpcFloatErrStub`'s shape: a parameterless signal hook reading the parked
`BSS_SIG_NUM` and `BSS_SIG_CODE`, writing the message with `sys_write` and
leaving via `exit_group(216)`. Pure syscalls, no unit dependency, never returns
(returning resumes the faulting instruction, forever).

Install is two `SigSetHook` calls — one for SIGSEGV(11), one for SIGBUS(7).
`SigSetHookAddr` falls through into `SigInstallAddr`, so each call both records
the hook and registers the SA_SIGINFO dispatch handler, which is what parks the
`si_code` the decoder reads.

SIGBUS gets its own message rather than being folded into "access violation":
it is a different fault (misaligned or invalid mapping, not an unmapped
address), and printing the plausible-but-wrong one is what this dialect refuses.
FPC numbers both 216.

### Known gaps, stated rather than hidden

- **Tier 2 is not done.** `try..except` is still blind: this reports and dies,
  it does not raise a catchable `EAccessViolation`. That is the ticket's own
  second tier and its own sitting — it means unwinding out of signal context
  into the exception machinery.
- **A STACK OVERFLOW reports 216, where FPC reports 202.** It arrives here as an
  ordinary `SEGV_MAPERR` on the guard page; telling it apart means comparing
  `si_addr` against the stack region. Belongs with
  [[bug-a-stack-overflow-fault-to-raise-loops-forever-without-an-sp-reset]],
  which is where the stack-fault machinery is being worked out.
- **x86-64 only**, as the ticket's per-arch note asked for. The other four
  signal runtimes shape the SA_SIGINFO parking differently; the flag errors on
  them by name rather than half-working.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 104s). New
`test/test_fpc_mem_errors.pas` — one source, five fault shapes selected by
argv[1] — wired into the core list asserting exit code, message and that the
fault happened after `before` printed, in both flag states.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
