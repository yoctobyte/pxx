---
summary: "ExitCode global + unit finalization execution + FPC Halt semantics (Halt sets ExitCode, runs finalizations, exits with ExitCode)"
type: feature
prio: 45
---

# ExitCode + finalization execution + Halt semantics (unblocks the erroru test family)

- **Type:** feature (Track A core — Halt lowering, program epilogue, init/final
  ordering; the ExitCode symbol itself could live in builtinheap once the
  codegen reads it)
- **Status:** backlog
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
