{$mode objfpc}
program test_shift_literal_width;

{ An untyped integer LITERAL shifted in an EXPRESSION must give the same answer
  on every target, and the same answer the CONST evaluator gives for the same
  text in the same program.

  decide-shift-operator-promotion-width (user, 2026-08-10) ruled that shifts
  happen at NATIVE width, and named `1 shl 40` answering 0 as the trap it was
  made to remove. The implementation read "native" as the TARGET's native width
  and dismissed the 32-bit targets with "native there IS 32 bits" — which left
  the trap standing on exactly those targets, and left them disagreeing with
  each other about it: `writeln(1 shl 40)` was 256 on i386 (x86 masks the shift
  count to 5 bits, so 40 became 8) and 0 on arm32, while `const K = 1 shl 40`
  in the same program was 2^40 on both, because ConstEval is Int64 everywhere.
  A literal has no declared width, so there is nothing for "native" to preserve
  — it promotes to 64 bits on every target.
  bug-a-an-untyped-literal-shift-is-target-width-on-32-bit-targets

  A DECLARED narrow variable is NOT this case and is deliberately absent here:
  it still promotes to the target's native width and no further, which is the
  ruling. test_shr_width.pas and test_shift_operand_width.pas guard that half.

  Every row below must be byte-identical on x86-64, i386, arm32, aarch64 and
  riscv32 — that target-independence IS the assertion. }

const
  K40 = 1 shl 40;
  KM  = (-8) shr 1;
var
  n: Integer;
begin
  writeln(K40);              { 1099511627776 — the const evaluator }
  writeln(1 shl 40);         { 1099511627776 — and the expression path agrees }
  writeln(KM);               { 9223372036854775804 }
  writeln((-8) shr 1);       { 9223372036854775804 }
  n := 40;
  writeln(1 shl n);          { 1099511627776 — a variable COUNT does not narrow
                               the literal operand either (FPC says 256 here;
                               that divergence is the 2026-08-10 ruling) }
  writeln(1 shl 62);         { 4611686018427387904 }
  writeln(3 shl 40);         { 3298534883328 }
  writeln((-1) shr 8);       { 72057594037927935 }
end.
