---
track: A
prio: 10
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, chasing why every Text write on wasm32 died with Runtime error 9)
tags: [wasm32, units, initialization, text-io, sysutils, random, silently-wrong]
summary: "On wasm32, NO unit's initialization section ran. The program driver emits the calls to the unit initialisers as machine code through EmitCallProc, but a wasm32 `main` is built from the body's chunks, so those bytes never reached the module. So a unit variable set in `initialization` read 0; textfile's Output/StdErr handles stayed 0, and every Text write went to fd 0 (EBADF, Runtime error 9); SysUtils' month names were empty and its separators NUL; and random's xoshiro state stayed all zeros. The driver now records which chunk the calls belong before, and WasmEmitMainWrapper makes them there."
owner: ""
---

# wasm32 never runs a unit's initialization section

```pascal
unit u; interface var V: Integer; implementation initialization V := 42; end.
program p; uses u; begin WriteLn(V); end.     { x86-64: 42   wasm32: 0 }
```

It fails the same way with the `begin ... end.` form of a unit's
initialization.

## What it broke

Every RTL unit whose initialization does work was left uninitialised, with no
error:

- **textfile**: `Output.Handle`, `StdErr.Handle` and `Input.Handle` all read 0
  (x86-64: 1 2 0). Every write through the Text RTL, including a plain
  `WriteLn(Output, 'x')`, went to fd 0 and failed with EBADF, which the program
  reports as "Runtime error 9 (I/O error)".
- **sysutils**: `ShortMonthNames[3]` was empty, and `DecimalSeparator` and
  `ThousandSeparator` were NUL, so `Format('%n', [1234.5])` printed
  `1 234 .50`. Its error-to-exception hooks were not installed either.
- **random**: the xoshiro state was never seeded, so it stayed all zeros and
  `Random64 <> Random64` was FALSE.

## Cause

`pasparser_prog.inc` runs the constant global initialisers
(`CompilePendingGlobalInits`), then `EmitCallProc(InitProcs[i])` for each unit
in dependency order, then the body. `EmitCallProc` writes machine code. On
wasm32, each top-level piece of work becomes its own function (a "main
chunk"), and the `main`/`_start` export is synthesised by
`WasmEmitMainWrapper` as a call to each chunk in turn. Nothing ever called the
init procs. DCE even kept them alive (`WasmDceMarkProc(InitProcs[i])`).

## The fix

- `pasparser_prog.inc`: on wasm32, record `WasmUnitInitAt :=
  WasmMainChunkCount` at the point where the other targets call the
  initialisers. That is after the global initialisers' chunks and before the
  first statement's, which keeps the order that fpjson depends on (see the
  comment at `CompilePendingGlobalInits`).
- `WasmEmitMainWrapper` calls every `InitProcs[j]` just before chunk
  `WasmUnitInitAt`, or after the last chunk if the body adds none.
- `WasmMainChunkCount` moved to defs.inc, because the Pascal driver is
  compiled before the wasm32 backend.

## Measured (2026-09-29, fixedpoint b21689af5303)

- `test/test_a_unit_initialization_runs_on_wasm32.pas` uses two sibling units:
  `uwasminita` (the `initialization` form, reading a typed constant) and
  `uwasminitb` (the `begin` form, which uses the first). It also uses
  SysUtils (month name, `%n`, separators), a global with an initialiser, and
  Text writes to Output and to the Text StdErr. Both streams equal FPC 3.2.2's
  on x86-64, i386, arm32, aarch64, riscv32, xtensa windowed/call0 and wasm32.
  With the previous compiler, wasm32 differs on both streams.
- Every wasm32 block in the Makefile (79) was run with the previous compiler
  and with this one. Nothing went from pass to fail, and the only blocks that
  went from fail to pass are this change's new rows. 18 blocks failed under
  both, because pulling them out of make breaks them. Cut off at the first
  make-only line, 13 of them pass under both. Of the other 5, three are
  compile-refusal tests (their expected non-zero exit trips `bash -e`), and two
  are fragments cut from a case/if block. Those two were run by hand, with
  identical output from both compilers.
- random on wasm32: `Random64 <> Random64` is TRUE (it was FALSE).

## Not in this fix

- **Finalization.** wasm32 does not run a unit's `finalization` either. The
  normal exit calls `PXXExitProcess` or the finalizer runner through the same
  `EmitCallProc`, which wasm32 drops. That is the same mechanism with a
  different call site, and it is the next change.
- **Division by zero.** `a div 0` inside `try ... except on EDivByZero` traps
  the wasm32 module ("integer divide by zero") instead of raising, with or
  without this fix. SysUtils' hook is installed now, but the division is not
  checked on wasm32.
- `test_text_write_float_and_pchar` still has no wasm32 row. Its console and
  Text StdErr lines now match. Its real-file line gets Runtime error 2 because
  the wasm runner gives the program no writable directory.
