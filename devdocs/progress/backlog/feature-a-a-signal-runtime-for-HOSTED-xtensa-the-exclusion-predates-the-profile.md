---
slug: feature-a-a-signal-runtime-for-HOSTED-xtensa-the-exclusion-predates-the-profile
track: A+S
prio: 35
type: feature
blocked-by: []
status: backlog
summary: "xtensa is the only hosted target with NO signal runtime — EmitSignalRuntimeForTarget has arms for five arches and falls through for xtensa, on purpose, because `FreeRTOS is not a Unix`. That rationale was written before the hosted xtensa profile existed, and under --platform=posix xtensa IS a Unix running on Linux via qemu. Not the 8-line IR_SET_SIGNAL port it looks like: the arm depends on a ~155-line runtime that does not exist. Unblocks 4 programs, not 1, because the three SA_SIGINFO refusals are gated on the same fact."
owner: unassigned
---

# A signal runtime for HOSTED xtensa

## Why this is not the small ticket it was filed as

[[bug-s-xtensa-has-no-ir-set-signal-arm-riscv32-does]] reads as "riscv32 has the
arm, port it" — and the arm really is eight lines. But it calls
`SigSetHookAddr`, and on xtensa nothing ever sets it:

```pascal
{ EmitSignalRuntimeForTarget, ir_codegen.inc }
if      TargetArch = TARGET_X86_64  then EmitSignalRuntime
else if TargetArch = TARGET_AARCH64 then EmitSignalRuntimeA64
else if TargetArch = TARGET_ARM32   then EmitSignalRuntimeArm32
else if TargetArch = TARGET_I386    then EmitSignalRuntime386
else if TargetArch = TARGET_RISCV32 then
begin
  if not EspBareBoot then EmitSignalRuntimeRISCV32;
end;
```

There is no `EmitSignalRuntimeXtensa`, and its absence is **recorded as
deliberate**, twice:

> *xtensa has no sibling stub on purpose … FreeRTOS is not a Unix and has no
> signal runtime at all.*

So porting the arm alone would emit a `call` to offset 0.

## The rationale is sound and its premise has expired

"FreeRTOS is not a Unix" is correct and is exactly why 33 PAL entry points are
refused on ESP. But it reasons from **arch to platform**, and since
`feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle` those are no longer
the same thing: under `--platform=posix` an xtensa binary is an ELF running on
Linux under `qemu-xtensa`, with `rt_sigaction` at syscall **226** (measured, see
[[feature-s-the-xtensa-row-of-the-posix-syscall-table]]).

**riscv32 is the precedent and it is already in the tree.** It is both an ESP
target and a hosted one, and it resolves this by gating on the PLATFORM —
`if not EspBareBoot then` — not on the arch. xtensa should do the same. That is
the whole design decision, and it needs a Track A/U call rather than a lane's
own read, because it reverses a documented exclusion.

## It unblocks four programs, not one

The three SA_SIGINFO refusals in `pasparser_expr.inc` are gated on the **same
fact**, not on a separate gap:

```pascal
if TargetArch = TARGET_XTENSA then
  Error(name + ' needs SA_SIGINFO, which this target''s signal runtime '
        + 'does not install (feature-signal-siginfo-ucontext)');
```

| program | blocked by |
| --- | --- |
| `test_signal_handler_callback_b336` | `IR_SET_SIGNAL` → the runtime |
| `test_signal_pc_rewrite` | SA_SIGINFO → the runtime |
| `test_signal_siginfo` | SA_SIGINFO → the runtime |
| `test_signal_sp_rewrite` | SA_SIGINFO → the runtime |

Every other hosted target installs with SA_SIGINFO, so an xtensa runtime built
to the same contract closes all four. That collapses two of the seven categories
in the xtensa tail into one ticket — worth more than the "1 row" the original
filing implied, and a reason to raise its priority rather than lower it for
being bigger. (Not verified past the compile gate: nothing can run these on
xtensa until the runtime exists, so a second blocker behind this one is
possible.)

## Scope

1. **`EmitSignalRuntimeXtensa`** in `ir_codegen_xtensa.inc`, modelled on
   `EmitSignalRuntimeRISCV32` (~155 lines of hand-encoded stub: dispatch,
   sethook, install, and the no-hook `SIG_DFL` + re-raise path that gives a
   proper killed-by-signal status). riscv is the right model — like arm64 and
   unlike x86-64 it has **no SA_RESTORER**, so kernel `struct sigaction` is
   `{ handler, flags, mask }`, ILP32 layout handler@0 flags@4 mask@8.
   `rt_sigaction=226`, `getpid=120`, `kill=123` on xtensa (measured);
   `sigsetsize = 8`.
   The xtensa-specific part is the **return path**: riscv `ret`s into the
   kernel's vdso `rt_sigreturn` trampoline with `ra` framed across the hook
   call. Call0's `a0` behaves like `ra`; the **windowed** ABI does not, and a
   handler entered by the kernel has no caller window to return through. Do
   Call0 first and treat windowed as a separate question, the same split the
   `CoSwitch` ticket makes.
2. **Gate on the platform, not the arch** — `if TargetPlatform = PLATFORM_POSIX`
   (or `not EspBareBoot`, matching riscv32 exactly). ESP keeps its deliberate
   exclusion; it is not a Unix and this ticket does not claim otherwise.
3. **The `IR_SET_SIGNAL` arm** — eight lines, once step 1 exists.
4. **Drop the `TARGET_XTENSA` refusal** in `pasparser_expr.inc` for the hosted
   profile only, keeping it for ESP.
5. `EmitDefaultSignalInstallForTarget` needs its xtensa arm too, or Ctrl-C
   stays ungraceful.

## Note on what already passes, so nobody reads it as coverage

`test_signal_default_revert_b336` matches on hosted xtensa **today** and is
wired into `test-xtensa` — but it installs no handler. It raises SIGTERM with
the default disposition and dies with status 143, which needs `kill`, not the
signal runtime. It is not evidence that any of this works.
