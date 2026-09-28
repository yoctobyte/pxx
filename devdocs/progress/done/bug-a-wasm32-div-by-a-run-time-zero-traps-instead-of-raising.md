---
track: A
prio: 15
type: bug
blocked-by: []
status: done
found-by: open row 072d1cf995 (wasm32 "wasm trap: integer divide by zero", exit 134, inside try/except EDivByZero); fixed by frankD
tags: [wasm32, exceptions, div, runtime-error]
summary: "On wasm32, integer `div` or `mod` by a divisor that is zero at run time trapped in the wasm instruction itself (`wasm trap: integer divide by zero`, exit 134). No `try ... except on EDivByZero` could catch it, and a program without SysUtils printed no `Runtime error 200`. Every native backend calls DivZeroCheckProc's handler first. wasm32 now does the same before i32/i64 div_s/div_u/rem_s/rem_u, then runs the ordinary post-call exception check."
owner: ""
---

# wasm32: div by a run-time zero traps instead of raising

```pascal
uses SysUtils;
b := 0;
try WriteLn(a div b);
except on E: EDivByZero do WriteLn('caught ', E.ClassName); end;
{ FPC, x86-64, i386, arm32, aarch64, riscv32, xtensa: caught EDivByZero }
{ wasm32: wasm trap: integer divide by zero, exit 134 }
```

## Cause and fix

wasm's `div`/`rem` instructions trap when the divisor is zero. The native
backends first call the handler that `DivZeroCheckProc` names. That handler is
`PXXDivZero`, which raises EDivByZero through SysUtils' hook and otherwise
stops with RE 200. `WasmIntBinop` emitted the instruction with no check.

`WasmDivZeroGuard` now runs before each integer div/mod. It stores the divisor
in a scratch local, and if the divisor is zero it calls the handler and sets
the divisor to 1. The instruction therefore cannot trap before
`WasmEmitExcCheck` unwinds, the same way it does after any other call. When
`DivZeroCheckProc` is -1 (`--no-div-check`, or the ESP platforms) nothing is
emitted, as on the other targets.

## Measured (2026-09-29, fixedpoint 4de42d8ec324)

- `test/test_div_by_a_run_time_zero_raises_on_wasm32.pas` covers:
  - div and mod on Integer, Int64, Cardinal and QWord;
  - a divide inside a call argument;
  - a divide on the right of a short-circuit `and`;
  - non-zero divisors, including a negative one.

  It equals FPC 3.2.2 on x86-64, i386, arm32, aarch64, riscv32, xtensa windowed
  and wasm32. With the previous compiler, only wasm32 differs (it stops at the
  first case, exit 134). The rows are x86-64, i386 and wasm32. The wasm32 row
  fails with the previous compiler.
- Raised in a nested function, the exception propagates through two frames
  (one of them holds a managed AnsiString local) to the caller's handler, the
  same as on x86-64.
- Without SysUtils, wasm32 now prints `Runtime error 200 (division by zero)`
  as x86-64 does. The process still does not exit 200 under wasmtime, because
  WASI refuses any exit status of 126 or higher. A plain `Halt(200)` does the
  same, so that limit comes from the runner and predates this fix.
- The 79 wasm32 Makefile blocks: no block changes status.
