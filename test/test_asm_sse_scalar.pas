program TestAsmSseScalar;
{ feature-inline-asm-xmm-operands, phase 1: scalar SSE reachable from a Pascal
  inline `asm ... end` block.

  Why this test is END-TO-END rather than an encoding assertion: the encodings
  were verified separately and exactly — the 21-instruction block in the ticket
  assembles to 88 bytes byte-identical to what gas produces for the same Intel
  syntax. Repeating that here would pin the bytes twice and tell us nothing
  about whether the operands were wired to the right storage. Running the
  arithmetic does: a correct opcode with the wrong ModRM still encodes, and only
  execution catches it.

  The gap this closes: inline asm had NO SSE mnemonics at all. There are three
  x86 encoders in this compiler — asmfront.inc (`.asm` files), asmenc.inc
  (Pascal inline asm) and asmtext.inc (compiler-emitted EmitAsmX64) — and only
  the third had them, so `asm movsd xmm0, x end` answered "unknown instruction"
  while the register names resolved fine. }

var failures: Integer;

procedure Check(got, want: Double; const what: AnsiString);
var d: Double;
begin
  d := got - want;
  if d < 0 then d := -d;
  if d > 1e-12 then
  begin
    WriteLn('FAIL ', what, ': got ', got:0:6, ' want ', want:0:6);
    failures := failures + 1;
  end;
end;

procedure CheckI(got, want: Int64; const what: AnsiString);
begin
  if got <> want then
  begin
    WriteLn('FAIL ', what, ': got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

var
  a, b, r: Double;
  fa, fb, fr: Single;
  i64: Int64;
  i32: Integer;

begin
  failures := 0;

  { load / store through memory operands, and the four scalar-double ops.
    movsd's STORE direction is a different opcode ($11), not the load with its
    operands swapped, so `movsd r, xmm0` exercises a distinct encoder path from
    `movsd xmm0, a`. }
  a := 3.5; b := 2.25;
  asm
    movsd xmm0, a
    movsd xmm1, b
    addsd xmm0, xmm1
    movsd r, xmm0
  end;
  Check(r, 5.75, 'addsd');

  asm
    movsd xmm0, a
    movsd xmm1, b
    subsd xmm0, xmm1
    movsd r, xmm0
  end;
  Check(r, 1.25, 'subsd');

  asm
    movsd xmm0, a
    movsd xmm1, b
    mulsd xmm0, xmm1
    movsd r, xmm0
  end;
  Check(r, 7.875, 'mulsd');

  a := 9.0; b := 4.0;
  asm
    movsd xmm0, a
    movsd xmm1, b
    divsd xmm0, xmm1
    movsd r, xmm0
  end;
  Check(r, 2.25, 'divsd');

  asm
    movsd xmm0, a
    sqrtsd xmm0, xmm0
    movsd r, xmm0
  end;
  Check(r, 3.0, 'sqrtsd (same reg as src and dest)');

  { xorpd against itself is the canonical zero idiom — and it is the one form
    where a wrong ModRM still "works" for reg,reg, so it is worth its own line. }
  asm
    xorpd xmm0, xmm0
    movsd r, xmm0
  end;
  Check(r, 0.0, 'xorpd self-zero');

  { A HIGH register (xmm8+) needs REX.B/REX.R, which is a different byte from
    the xmm0-7 forms. Without it this silently targets xmm0-7 instead. }
  a := 1.5; b := 2.5;
  asm
    movsd xmm9, a
    movsd xmm10, b
    addsd xmm9, xmm10
    movsd r, xmm9
  end;
  Check(r, 4.0, 'addsd on xmm9/xmm10 (REX-extended registers)');

  { single precision: the F3 prefix family. }
  fa := 1.5; fb := 0.25;
  asm
    movss xmm0, fa
    movss xmm1, fb
    addss xmm0, xmm1
    movss fr, xmm0
  end;
  Check(fr, 1.75, 'addss');

  { single <-> double conversion }
  fa := 2.5;
  asm
    movss xmm0, fa
    cvtss2sd xmm0, xmm0
    movsd r, xmm0
  end;
  Check(r, 2.5, 'cvtss2sd');

  { int -> double, both GP widths. The 64-bit source needs REX.W; the 32-bit
    one must NOT have it, and getting that backwards reads the wrong half. }
  i64 := 1234567890123;
  asm
    cvtsi2sd xmm0, i64
    movsd r, xmm0
  end;
  Check(r, 1234567890123.0, 'cvtsi2sd from Int64 (REX.W)');

  i32 := -4242;
  asm
    cvtsi2sd xmm0, i32
    movsd r, xmm0
  end;
  Check(r, -4242.0, 'cvtsi2sd from Integer (no REX.W)');

  { double -> int. cvttsd2si TRUNCATES, cvtsd2si ROUNDS — the pair is the whole
    reason both opcodes exist ($2C vs $2D), and having only the truncating one
    is a trap, so pin the difference on the same input. }
  a := 2.7;
  asm
    movsd xmm0, a
    cvttsd2si rax, xmm0
    mov i64, rax
  end;
  CheckI(i64, 2, 'cvttsd2si truncates 2.7 -> 2');

  asm
    movsd xmm0, a
    cvtsd2si rax, xmm0
    mov i64, rax
  end;
  CheckI(i64, 3, 'cvtsd2si rounds 2.7 -> 3');

  if failures = 0 then WriteLn('asm sse scalar ok')
  else WriteLn('asm sse scalar FAILED ', failures);
end.
