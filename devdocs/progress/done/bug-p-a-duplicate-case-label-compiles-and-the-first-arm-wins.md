---
track: P
tags: [pascal, case, diagnostics, fpc-parity]
prio: 30
type: bug
blocked-by: []
summary: "pxx accepts a case statement with the same label twice. The first arm silently wins, and the second is dead code. FPC refuses it ('duplicate case label'). Found when ir_codegen_aarch64.inc briefly had two `IR_ASM:` arms: the self-host build passed, and only the FPC seed canary caught it."
status: done
owner: claude-dupwt
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


# Fixed 2026-11-19 (claude-dupwt), within the dialect decision

**The check already existed. It is opt-in by an owner decision:** 306a75277f,
"PXX is lax by design". `--strict-case` / `{$STRICT_CASE ON}` reports
`duplicate or overlapping case label`. The lax default keeps first-match for
overlapping labels on purpose, and test_cross_case_range relies on a deliberate
'y' / 'x'..'z' overlap. Making it an error for all user code would reverse that
decision, so this does not.

What the ticket needs is the SELF-HOST build catching it, and that is now true:
compiler/compiler.pas opts in with `{$ifndef FPC}{$STRICT_CASE ON}{$endif}`
(real FPC rejects duplicates anyway). Checked:
- the compiler builds clean under it, with an unchanged fixedpoint hash
  (a9195ba16df2), so there are no duplicates in the compiler today;
- the directive reaches a duplicate inside an `{$I}` include, the shape of
  ir_codegen_aarch64.inc: `pascal26:6: error: duplicate or overlapping case
  label  in: inc1.inc`;
- the same program without the directive still compiles and prints `first`.

Not done: naming BOTH positions. The diagnostic names the second label only.
A user who wants fpc's error for their own code passes --strict-case or
--strict-fpc.
