# Function `Result` (float) read-modified inside a loop miscompiles to 0

- **Type:** bug
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-18 (found while building the transcendental math lib)

## Symptom

Inside a function returning `Double`, reading-and-writing `Result` in a loop
loses the value — the result comes out 0.

```pascal
function E: Double;
var kc: Integer;
begin
  Result := 1.359141;
  kc := 1;
  while kc > 0 do begin Result := Result * 2.0; kc := kc - 1; end;  { -> 0, not 2.718 }
end;
```

Narrowed:
- A float **local** read-modified in the same loop is **fine**
  (`s := s * 2.0` in a `while`/`for` → correct).
- `Result := Result * 2.0` **once, no loop** is **fine**.
- `Result := Result * 2.0` **inside a loop** → 0.

So it is specifically the function-result float slot being read back across loop
iterations.

## Likely cause

The float Result is probably kept in xmm0 / a fixed location across the function,
and the loop body's reload/store of Result (mixed with the integer counter update)
clobbers it or reloads a stale/zero value each iteration. Compare the working
float-local path — the local has a stable stack slot that the loop reloads
correctly. Audit how AN_ASSIGN to the function-result symbol lowers when the RHS
also reads the result, within a loop body.

## Workaround in place

lib/rtl/math.pas (Exp, ArcTan) accumulates into a plain local and assigns Result
once at the end.

## Acceptance

`Result := Result <op> e` inside a loop in a Double function yields the correct
value; FPC byte-identical; `make test` + `make cross-bootstrap` green.

## Log
- 2026-06-18 — opened from the math-lib arc; math.pas works around it.
- 2026-06-20 — **FIXED (x86-64), commit c3c4e5a.** Root cause was NOT the loop
  body — it was the function epilogue. The x86-64 `EmitProcEpilog` (symtab.inc)
  loaded a float Result into xmm0 via `EmitLoadVar` but did not bridge it to rax;
  the internal call ABI / value model carries a float return as double-bits in
  rax (the caller does `movq xmm0, rax` after the call). It only worked when rax
  happened to still hold the bits from the last store; a loop's condition
  (`setcc`/`test`) clobbers rax → the caller read 0. Disassembly proof: at loop
  exit the epilogue did `movsd xmm0,[rbp-8]; leave; ret` with rax = 0 from the
  exited condition. Fix: emit `movq rax, xmm0` after the float result load,
  mirroring the IR_LOAD_SYM bridge. test/test_float_result_loop.pas (while+for
  RMW of Result) in test-core. Byte-identical self-host + cross-bootstrap + cross
  suites green.
  NOTE (cross): aarch64/arm32/xtensa/riscv do not have this bug because they
  carry float returns in their integer return register (no SSE/xmm split). In
  fact those targets currently **Error** on a float function result altogether
  ("only ordinal/pointer/string function results supported yet") — float
  function returns on cross targets are a separate, larger unimplemented gap, not
  tracked by this ticket.
