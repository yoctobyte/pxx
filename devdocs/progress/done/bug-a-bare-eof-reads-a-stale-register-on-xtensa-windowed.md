---
track: A
prio: 20
type: bug
blocked-by: []
status: done
found-by: frankD (2026-09-29, the special-id census for bug-a-reallocmem-builds-only-on-x86-64); routed by frankuser as flagship (xtensa windowed is the ESP32-S3 ABI)
tags: [backend, xtensa, windowed-abi, stdin, eof]
summary: "On xtensa windowed, bare `Eof` (standard input) returned whatever a2 held before the call. `while not Eof do Readln(x)` over `2 3` printed `2 FALSE`; at end of input the loop never ended and read zeros forever. Under the windowed ABI a call's result arrives in the caller's a10. Every other value-returning call moves it to a2, but the -210 arm did not. Call0, riscv32 and the other backends were right."
owner: ""
---

# Bare `Eof` reads a stale register on xtensa windowed

```pascal
while not Eof do begin Readln(x); Write(x, ' ') end;
Writeln(Eof);
{ stdin "2\n3\n": FPC and x86-64 print `2 3 TRUE`; xtensa windowed `2 FALSE` }
```

## Cause and fix

The parser lowers bare `Eof` and `Eof()` to special call id -210, and each
backend calls the builtin unit's `PXXStdinEof`. In ir_codegen_xtensa.inc the
arm was just `EmitCallProc`. Under Call0 the result is in a2, so that is
enough. Under the windowed ABI (`call8`) the callee's a2 is the caller's a10.
The general call path, and each helper that returns a value, moves a10 to a2
afterwards; this arm did not. The arm now does that move when the ABI is
windowed.

The other special-call arms in the xtensa backend that call `EmitCallProc`
either return nothing (SetLength, the Readln family) or already move the
result.

## Measured (2026-09-29, fixedpoint 8c0075b5edd6)

- `test/test_bare_eof_on_stdin_on_every_target.pas` with `.in`. It reads four
  lines until `Eof`, asks `Eof` twice between reads (both answers must agree),
  then prints the final `Eof` and uses it in an `if`. `.expected` is FPC's.
- Rows: x86-64, i386, riscv32, xtensa windowed and xtensa Call0. It equals FPC
  on all five.
- The previous compiler passes on x86-64, i386, riscv32 and Call0. On
  windowed, `Eof` never becomes true: the program prints `2 3 -7 40` and then
  zeros until it is killed. The rows carry a timeout for that reason.
- wasm32 still refuses bare `Eof`. That is deliberate and in LOGBOOK: wasm32
  has no stdin at all (no PXXSysRead arm, no Readln lowering), so a
  `PXXStdinEof` call there would answer TRUE with input waiting.
