---
summary: "ExitCode global + unit finalization execution + FPC Halt semantics (Halt sets ExitCode, runs finalizations, exits with ExitCode)"
type: feature
prio: 45
owner: claude-A
---

# ExitCode + finalization execution + Halt semantics (unblocks the erroru test family)

- **Type:** feature (Track A core — Halt lowering, program epilogue, init/final
  ordering; the ExitCode symbol itself could live in builtinheap once the
  codegen reads it)
- **Status:** done
- **Opened:** 2026-07-14
- **Found by:** Track B FPC-conformance burn-down. Filed under A because every
  piece is codegen/parser, not RTL surface.

## What FPC does (and the testsuite's `erroru.pp` depends on, in order)

1. `ExitCode: Longint` is a writable global in System scope.
2. `Halt(n)` sets `ExitCode := n`, then runs **unit finalization sections**
   (reverse init order), then terminates with `ExitCode`.
3. `Halt` (no arg) = terminate with current `ExitCode`; normal program end
   also exits with `ExitCode`.
4. A finalization section may WRITE `ExitCode` (erroru's `error_unit_exit`
   checks the recorded exit code against the accepted/required error number
   and then **zeroes it**, turning an expected `halt(100)` into process exit
   0 — that is how every `accept_error/require_error` test passes).

## pxx today

- No `ExitCode` symbol at all (`pascal26: undefined variable (exitcode)`).
- `initialization` sections compile into `__init_<unit>` procs and run before
  main (ParseInitializationSection, parser.inc); `finalization` bodies are
  token-skipped and never executed (`{ 'finalization' + its body are skipped }`).
- `Halt(n)` lowers straight to the exit syscall — no finalization pass.

## Scope sketch

- Parse finalization like initialization into `__fini_<unit>` procs; run them
  reverse-order from a common exit stub.
- Route Halt(n) / Halt / falling-off-main through that stub: store n (if
  given) to ExitCode, run finis, exit(ExitCode). Guard against recursive Halt
  from inside a finalization (FPC keeps going with the new code).
- `erroru.pp` additionally wants `erroraddr: Pointer` (nil-able) and
  `GetFPCHeapStatus/TFPCHeapstatus` — stub-able, but out of scope here; the
  finalization/ExitCode machinery is the load-bearing part.

## Unblocks (conformance skip list)

`tstring2.pp`, `tstring5.pp`, `texception3.pp`, `tobject1.pp` (partly — also
needs constructor `fail`), and every future erroru-using test the curated
categories pick up.

---

## Done 2026-08-21 — and half of it was already there

### The ticket's "pxx today" was stale

Two of its three bullets no longer held. `finalization` sections **are** parsed
into `__fini_<unit>` procs and **are** run in reverse init order, from the main
body and from every Halt site, behind a run-once guard
(`bug-unit-finalization-not-executed`, since this ticket was filed). What was
actually missing was **one thing: `ExitCode` did not exist**, and so nothing
could observe or influence the exit status.

Checking that first is what kept this to a small change. The ticket's scope
sketch would have rebuilt the finalization machinery that was already correct.

### One premise was wrong, and measurement is what said so

The ticket asserts:

> 3. `Halt` (no arg) = terminate with current `ExitCode`

**It does not.** FPC 3.2.2, measured with a finalization that reports what it
sees: `ExitCode := 9; Halt;` behaves exactly as `Halt(0)` — the finalization
sees **0**, not 9. `Halt` is `Halt(0)`; it RESETS the code. Everything else in
the ticket's list checked out. The full oracle, all six built and run against
FPC before a line was changed:

| program body | FPC | pxx after |
| --- | --- | --- |
| `writeln('body')` | 1 | 1 |
| `Halt(100)` | 0 | 0 |
| `Halt(5)` | 6 | 6 |
| `ExitCode := 9` | 10 | 10 |
| `ExitCode := 9; Halt` | **1** | 1 |
| `ExitCode := 9; Halt(2)` | 3 | 3 |

(the observing unit's finalization stores `ExitCode + 1`, or 0 when it sees 100
— erroru.pp's own idiom, which is why those numbers are all off by one.)
Plus: a `Halt` **inside** a finalization exits with its own code and does not
re-enter the runner — FPC 77, pxx 77.

### What was built

- **`ExitCode: Longint` in `builtinheap`'s interface.** FPC puts it in System
  scope; builtinheap is linked into every binary and its interface names resolve
  bare, so that is the cheapest honest home. A program declaring its own
  `ExitCode` shadows it, exactly as under FPC — checked.
- **`Halt` lowering re-ordered.** `ExitCode := arg` (or 0 for a bare `Halt`)
  **before** the finalization runner, and the status **re-read after** it. That
  order IS the feature: terminating with the argument would make a
  finalization's write invisible, which is precisely the erroru idiom the ticket
  exists to unblock.
- **The main-body epilogue** now calls a Pascal `PXXExitProcess` (`Halt(ExitCode)`)
  instead of emitting a raw `exit(0)`.

### The bit worth stealing: no new per-arch emitter

"Terminate with the value of a global" would have needed a new emitter in each
of **six** backends. "Terminate with a computed VALUE" is something the AN_HALT
lowering already does on all six. So the exit path is written as Pascal —
`procedure PXXExitProcess; begin Halt(ExitCode); end;` — and the existing
lowering carries it everywhere for free. Verified by running the `Halt(2)` case
on **i386, arm32, aarch64 and riscv32**: exit 3 on all four, same as native.

A fallback stays for a build with no builtinheap (bare/ESP): no `ExitCode`
symbol, no `PXXExitProcess`, and Halt terminates with its argument as before.

### An FPC quirk found on the way, and deliberately NOT copied

FPC does not flush stdout after its unit finalizations, so a `writeln` in a
finalization **vanishes** unless the section calls `Flush(Output)` itself. pxx's
prints. That is a superset, not a divergence, and the tests therefore assert on
the exit STATUS — which matches FPC exactly — while treating the printed line as
pxx's own. Copying the quirk would be copying a bug.

(An earlier read of this said `Flush` was missing from pxx's RTL. It is not —
`Flush(Output)` compiles and works; the probe unit simply had no `uses
textfile`, where both live. The only difference from FPC is scope: FPC puts
them in System, so they need no uses clause. Not chased.)

### Gate

`test/test_exitcode_{normal_end,halt_arg,halt_bare,halt_in_finalization}.pas`
over `test/exitcodeunits/` — all four corners, each asserting stdout **and**
exit status, each status verified identical to FPC 3.2.2.
`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

### Still out of scope, as the ticket said

`erroraddr: Pointer` and `GetFPCHeapStatus` / `TFPCHeapStatus`, which
`erroru.pp` also wants. They are stubbable and independent; the load-bearing
half is done. The conformance skip-list entries the ticket names
(`tstring2.pp`, `tstring5.pp`, `texception3.pp`, `tobject1.pp`) should be
re-tried now — that is Track T's sweep, not this session's.

## Log
- 2026-08-21 — resolved, commit 9a2c8e75e.
