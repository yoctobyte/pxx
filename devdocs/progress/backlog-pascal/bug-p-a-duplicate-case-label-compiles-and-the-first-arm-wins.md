---
track: P
tags: [pascal, case, diagnostics, fpc-parity]
prio: 30
type: bug
blocked-by: []
summary: "pxx accepts a case statement with the same label twice. The first arm silently wins, and the second is dead code. FPC refuses it ('duplicate case label'). Found when ir_codegen_aarch64.inc briefly had two `IR_ASM:` arms: the self-host build passed, and only the FPC seed canary caught it."
status: open
owner: unassigned
---

# A duplicate case label compiles, and the first arm wins

Found 2026-11-14 while adding C inline asm for aarch64. A new `IR_ASM:` arm
went into `IREmitNodeAarch64` above an existing one that replays Pascal
`asm` blocks. pxx compiled the compiler, the fixedpoint verified, and the
quick tier passed. The FPC seed canary failed with

    ir_codegen_aarch64.inc(2131,11) Error: duplicate case label

Under pxx the first arm took every IR_ASM. A Pascal `asm` block on aarch64
would have gone down the C path without any error.

## Want

A duplicate constant label in one `case` (including overlapping ranges) is
a compile-time error that names both positions, as FPC does. That makes
the self-host build catch this, not just the seed canary.

## Repro

    {$mode objfpc}{$H+}
    program dupcase;
    var k: Integer;
    begin
      k := 1;
      case k of
        1: WriteLn('first');
        1: WriteLn('second');
      end;
    end.

FPC: `Error: duplicate case label`. pxx: compiles, prints `first`.
