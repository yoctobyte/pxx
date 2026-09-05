---
slug: feature-a-a-signal-runtime-for-HOSTED-xtensa-the-exclusion-predates-the-profile
track: A+S
prio: 35
type: feature
blocked-by: []
status: done
summary: "STALE AS FILED, verified by RUNNING. Hosted xtensa HAS a signal runtime: test_signal_altstack builds and runs under qemu and reports handler-off-faulting-stack=TRUE, which cannot happen without one. The exclusion was already re-keyed off the arch under ruling-the-xtensa-signal-exclusion-is-keyed-on-arch-and-the-premise-expired, and ir.inc's own comment records the change. What was genuinely still missing was the SIBLING half -- the ucontext PC/SP offsets -- which is why these two were taken as one group and closed together. Both now measured (PC=20, SP=56); fault-to-raise and stack-overflow-to-exception both work on xtensa. See feature-a-xtensa-ucontext-pc-sp-offsets."
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


## 2026-09-04 (frankb-78) — one of the two stated reasons for the windowed half is retired

Not taken, and nothing measured about signals. Recording it because the
justification changed underneath this ticket rather than because the work did.

`EmitSignalRuntimeXtensa`'s own header said windowed was excluded because *"a
windowed unwind needs the register windows spilled first, which is the same
reason TargetHasProcCleanupFrame is Call0-only"*. Both halves of that sentence
went on 2026-09-04 (`2ec3e61c5`, `6a22f26d4`): the windowed unwind has its spill
and that predicate is no longer Call0-only.

**That does not make windowed signals work** — it makes the recorded reason
false. What actually remains is narrower and **unmeasured**: the stub is Call0
code (ends in `RET`, treats `a0` as a plain return address, written against a
Call0 frame), so whether it works inside a windowed program is a question nobody
has run. Its entry handling is already ABI-independent — the kernel enters a
handler with the call4 convention whatever the handler was compiled with, which
that stub's own dead-code note measured — so the remaining work may be small.

The comment is corrected in place and now points here rather than at a retired
premise. `pyparser.inc`'s and `pasparser_expr.inc`'s `__pxxSig*` refusals go
through `TargetHasSignalRuntime` and are unaffected: they refuse a runtime that
is genuinely absent, for a reason that is still true.

**The generalisation this came from**, worth more than the instance: *a
capability fix retires the justification for an exclusion, so grep for what was
excluded FOR THAT REASON* — not only for the sibling code path. Two sites in
`ir_codegen_xtensa.inc` cited the unwind gap for exclusions that were not the
unwind, and both would have read as current to the next person.


## Resolved 2026-09-05 (frankS) — stale premise, live sibling, closed as a pair

### The premise did not survive being run

This ticket says *"xtensa is the only hosted target with NO signal runtime —
EmitSignalRuntimeForTarget … falls through for xtensa"*. Measured instead of
read:

```
test_signal_altstack, --target=xtensa --platform=posix --xtensa-soft-mulhigh
  recursing
  code=2
  handler-off-faulting-stack=TRUE
  exit=0
```

A handler that runs, takes a fault, and reports it ran off the faulting stack is
not a target without a signal runtime. `ir_codegen.inc:1494` carries the arm,
gated on `TargetHasSignalRuntime` rather than on an arch list, and
`UContextPCOffset`'s comment records exactly when this changed: *"That stopped
being true when the signal exclusion was re-keyed off the arch … hosted xtensa
now has a signal runtime."*

### Why it was still worth holding, and why as a PAIR

The ticket's real content had migrated into its sibling. With the runtime
present, `test_signal_pc_rewrite` and `test_signal_sp_rewrite` reached
`UContextPCOffset` and stopped at its `-1` guard — a **different** refusal, one
level further in. So "xtensa cannot do signals" had become "xtensa can do
signals but cannot turn a fault into a raise", and only one of those two
sentences was written down anywhere.

**Taken as one group on that basis.** A signal runtime and the ucontext offsets
that disagree about where PC and SP live would be two half-fixes each passing
its own gate. Closing them together is what makes that impossible here.

The measured half is in `feature-a-xtensa-ucontext-pc-sp-offsets`: PC=20, SP=56,
two agreeing sources each, probe calibrated on riscv32 first, three rows wired
in `test-core` and byte-identical to the x86-64 run under local qemu.

### For the next reader

Both tickets in this pair were STALE IN THE SAME DIRECTION — each described a
gap wider than the one that remained, and in both cases the discriminator was
running a program rather than reading the source. That is now three this session
(the dyn-array function result was the third). The common shape: a refusal is
lifted somewhere, the tickets that cite it are not updated, and **the cited code
still exists and still refuses something**, so reading confirms the ticket.
