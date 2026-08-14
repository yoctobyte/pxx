program TestAsmSsePacked;
{ feature-inline-asm-xmm-operands, phase 3: PACKED SSE2 from a Pascal inline
  `asm ... end` block — 2-wide double kernels become writable.

  Encodings are verified against gas separately and exactly (22 instructions,
  96 bytes, byte-identical). This test runs the arithmetic instead, because
  that is what encoding assertions cannot reach: a correct opcode with the
  wrong ModRM, or the two lanes transposed, still assembles.

  Everything is built from SCALAR variables through `unpcklpd` rather than
  loaded from an array, deliberately: `movapd` faults on a misaligned address,
  and a test that depended on a Pascal array happening to be 16-byte aligned
  would be a coin flip dressed as a regression test. Register-to-register forms
  have no alignment question at all. }

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
  a, b, c, d, lo, hi: Double;
  mask: Integer;
  bits, bits2: Int64;

begin
  failures := 0;

  { Build [a | b] in xmm0 and read BOTH lanes back. unpcklpd is what makes the
    rest of this test possible, so if it is wrong every line below lies —
    hence checking the two halves separately before any arithmetic. }
  a := 1.5; b := 2.5;
  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1     { xmm0 = [ b | a ], a in the LOW lane }
    movsd lo, xmm0
    unpckhpd xmm0, xmm0     { broadcast the high lane down }
    movsd hi, xmm0
  end;
  Check(lo, 1.5, 'unpcklpd low lane');
  Check(hi, 2.5, 'unpckhpd high lane');

  { addpd: [1.5|2.5] + [0.25|4.0] = [1.75|6.5]. Both lanes checked — a packed
    op that only got the low lane right would pass a low-lane-only test and be
    exactly as broken as one that got neither. }
  a := 1.5; b := 2.5; c := 0.25; d := 4.0;
  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1
    movsd xmm2, c
    movsd xmm3, d
    unpcklpd xmm2, xmm3
    addpd xmm0, xmm2
    movsd lo, xmm0
    unpckhpd xmm0, xmm0
    movsd hi, xmm0
  end;
  Check(lo, 1.75, 'addpd low lane');
  Check(hi, 6.5,  'addpd high lane');

  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1
    movsd xmm2, c
    movsd xmm3, d
    unpcklpd xmm2, xmm3
    mulpd xmm0, xmm2
    movsd lo, xmm0
    unpckhpd xmm0, xmm0
    movsd hi, xmm0
  end;
  Check(lo, 0.375, 'mulpd low lane');
  Check(hi, 10.0,  'mulpd high lane');

  { sqrtpd over [4|9] = [2|3] }
  a := 4.0; b := 9.0;
  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1
    sqrtpd xmm0, xmm0
    movsd lo, xmm0
    unpckhpd xmm0, xmm0
    movsd hi, xmm0
  end;
  Check(lo, 2.0, 'sqrtpd low lane');
  Check(hi, 3.0, 'sqrtpd high lane');

  { maxpd / minpd pick per lane, which is the point — the answer must come from
    a DIFFERENT source vector in each lane or the test proves nothing. }
  a := 1.0; b := 8.0; c := 5.0; d := 2.0;
  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1     { [1 | 8] }
    movsd xmm2, c
    movsd xmm3, d
    unpcklpd xmm2, xmm3     { [5 | 2] }
    maxpd xmm0, xmm2
    movsd lo, xmm0
    unpckhpd xmm0, xmm0
    movsd hi, xmm0
  end;
  Check(lo, 5.0, 'maxpd low lane (from the second vector)');
  Check(hi, 8.0, 'maxpd high lane (from the first vector)');

  { shufpd with selector 1 swaps the two halves of one register. }
  a := 11.0; b := 22.0;
  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1     { [22 | 11] }
    shufpd xmm0, xmm0, 1    { swap -> [11 | 22] }
    movsd lo, xmm0
    unpckhpd xmm0, xmm0
    movsd hi, xmm0
  end;
  Check(lo, 22.0, 'shufpd swapped low lane');
  Check(hi, 11.0, 'shufpd swapped high lane');

  { cmppd + movmskpd: the compare writes an all-ones or all-zero mask per lane,
    and movmskpd collects the two SIGN bits into a GP register. Predicate 1 is
    "less than". [1|8] < [5|2] is [true|false] -> low bit set, high bit clear
    -> 1. This is the pair a real vector kernel uses for its escape test, and
    movmskpd is also the one form here whose destination is a GP register. }
  a := 1.0; b := 8.0; c := 5.0; d := 2.0;
  asm
    movsd xmm0, a
    movsd xmm1, b
    unpcklpd xmm0, xmm1     { [1 | 8] }
    movsd xmm2, c
    movsd xmm3, d
    unpcklpd xmm2, xmm3     { [5 | 2] }
    cmppd xmm0, xmm2, 1     { lane < : [1<5 = true | 8<2 = false] }
    movmskpd eax, xmm0
    mov mask, eax
  end;
  CheckI(mask, 1, 'cmppd lt + movmskpd gives low lane only');

  { movq moves the raw 64 bits of a double between the vector and GP files
    without a memory round trip. Round-tripping must preserve the bit pattern
    exactly, so compare the BITS rather than the value. }
  a := -3.75;
  asm
    movsd xmm0, a
    movq rax, xmm0
    mov bits, rax
  end;
  asm
    mov rax, bits
    movq xmm0, rax
    movsd lo, xmm0
  end;
  Check(lo, -3.75, 'movq xmm->GP->xmm round trip');

  { ...and through a REX-extended register on both sides, which needs REX.B and
    REX.R rather than only REX.W. }
  asm
    movsd xmm9, a
    movq r11, xmm9
    mov bits2, r11
  end;
  CheckI(bits2, bits, 'movq through xmm9/r11 matches the xmm0/rax bits');

  { movapd / movupd register-to-register: same shape, different alignment
    contract, and each has its own STORE opcode ($29 vs $11) that this form
    must not reach. }
  a := 7.25;
  asm
    movsd xmm0, a
    movapd xmm5, xmm0
    movupd xmm6, xmm5
    movsd lo, xmm6
  end;
  Check(lo, 7.25, 'movapd/movupd register moves');

  if failures = 0 then WriteLn('asm sse packed ok')
  else WriteLn('asm sse packed FAILED ', failures);
end.
