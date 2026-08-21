---
track: U
prio: 10
type: meta
blocked-by: []
summary: "Parking lot for the whole FPC error-REPORTING parity cluster: the SEGV default, stack overflow's 202, --mimic-fpc not implying the --fpc-*-errors flags, tier-2 catchable EAccessViolation, and the per-arch gap. All low prio by the recorded principle that a strict flag governs compilation, not death. NOT in scope: emitted nil checks, which are language-level catchability and stay ranked."
status: rainy-day
owner: unassigned
---

# Meta: the FPC error-reporting parity cluster (rainy day)

- **Track U**, parked 2026-08-21 by the user while going over the decision queue:

> *"i'm not bothered by it and hunting this down at this stage of development is
> a waste of time. we could make a meta ticket about this for rainy days"*

This ticket exists so the cluster is findable as ONE thing, and so nobody
re-derives the analysis. Everything below is understood; none of it is urgent.

## Why it is parked, and why that is principled rather than lazy

CLAUDE.md now records the boundary (user, same day): **a strict flag's scope is
COMPILATION, not death.** `--strict-fpc` / `--mimic-fpc` govern how source is
compiled and how output is formatted; they do not govern how a program dies.
Runtime-error numbers, exit codes and fault messages stay ours by default.

> *"We seek LANGUAGE compliance, not error-handling compliance."*

So parity work whose subject is error REPORTING is low prio by the same call
that makes float accuracy low prio under Track F. That is the whole cluster.

## What is in the cluster

| open question | state |
| --- | --- |
| **The SEGV default** — report-and-re-raise (message + core dump + exit 139) vs FPC's exit 216 | never answered; [[decide-segv-runtime-error-default]], narrowed 2026-08-21 and parked here with this ticket |
| **Stack overflow should report 202, not 216** | one comparison of `si_addr` against the saved SP, both already in hand inside the `--fpc-mem-errors` stub. Needs no headroom, no flag, no exception class — **fold it in opportunistically if anyone touches that stub**; it does not justify a session |
| **Should a stack overflow raise `EStackOverflow` by itself?** | [[decide-should-a-stack-overflow-raise-estackoverflow-by-itself]], parked separately. Direction recorded: (b) by default with FPC's numbering under strict-fpc. Real blocker is headroom, not design — the raise must land on the main stack past the guard page |
| **`--mimic-fpc` implies NEITHER `--fpc-mem-errors` nor `--fpc-float-errors`** | an inconsistency nobody decided: a user who asked to mimic FPC still gets exit 139 and quiet IEEE floats. Both flag names literally begin with `fpc-` |
| **Tier 2: catchable `EAccessViolation` from signal context** | the parent bug's own second tier. Means unwinding out of signal context into the exception machinery. Largely dissolved by the nil checks below — the common shapes never become signals |
| **`--fpc-mem-errors` is x86-64 only** | the other four signal runtimes shape SA_SIGINFO parking differently; the flag errors by name on them rather than half-working. Deliberate |

## NOT in this cluster — do not park it with the rest

**[[feature-a-emitted-nil-checks]] stays ranked (Track A, prio 55).** It looks
adjacent and is not: it is not about how a dead program reports itself, it is
about the program **not dying** — a nil receiver caught at the check site,
raised as an ordinary catchable `EAccessViolation` at a named line, on targets
that have no signal runtime at all (xtensa has none by design; riscv32 skips it
under `--esp-profile=bare`).

The user's reason for wanting it was explicit: *"potentially some of those
otherwise-segfaults would be catchable with an exception catcher, and that is
genuinely useful."* That is language-level behaviour, not FPC parity. The
`Runtime error 216` string it prints without sysutils is incidental.

If a future reader sweeps the nil checks in here because both mention 216, that
is the mistake this section exists to prevent.

## Machinery, so a later session starts from facts

- The trap-plus-hook family in `compiler/builtin/builtinheap.pas`: a routine with
  a proc-typed hook slot, nil = message + `Halt(n)`, upgraded by sysutils'
  `initialization` to a catchable raise. Four shipped —
  `PXXDivZeroHook`→`EDivByZero`, `PXXOverflowHook`→`EIntOverflow`,
  `PXXRangeErrorHook`→`ERangeError`, `PXXIoErrorHook`→`EInOutError`.
  `EAccessViolation` exists (`sysutils.pas:125`) and is unused; `EStackOverflow`
  does **not** exist.
- `--fpc-mem-errors` landed 2026-08-21 (`6b5bbd6cc`), tier 1, x86-64, opt-in.
  `test/test_fpc_mem_errors.pas` asserts BOTH directions (216 with the flag, 139
  without) precisely so a default flip is a failing row, not a silent change.
- The third shape nobody considered until 2026-08-21: reset the disposition to
  `SIG_DFL` and RETURN — the fault re-executes and the kernel default applies, so
  you get the message AND the core dump. The choice was never message-xor-core.

## How to unpark

Any one of these is a reason: a user complaint about a bare `Segmentation fault`;
a harness that keys on FPC exit codes; or someone in that stub for another
reason, who should take the 202 row while they are there.
