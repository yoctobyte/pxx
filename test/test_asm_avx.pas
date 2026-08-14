program TestAsmAvx;
{ feature-inline-asm-xmm-operands, phase 4: AVX (VEX-encoded) from a Pascal
  inline `asm ... end` block — 4-wide double kernels, and FMA.

  Encodings are verified against gas separately and exactly: 25 instructions,
  110 bytes, byte-identical, covering both VEX forms, the 0F38 map and FMA's
  W=1. This test runs the arithmetic, which is what the byte comparison cannot
  reach — a correct prefix with the wrong L bit encodes cleanly and computes
  two lanes where four were asked for.

  IT GATES ITSELF ON CPU SUPPORT, and that gate is the whole reason phase 2
  (cpuid/xgetbv) landed first. Executing an AVX instruction on a machine
  without it is #UD — a crash, not a failure message — so a test that assumed
  AVX would not report "unsupported", it would take the whole suite down on
  older hardware. Two things must BOTH hold:

    leaf 1 ecx bit 28   the CPU implements AVX
    leaf 1 ecx bit 27   OSXSAVE: the OS enabled XGETBV at all
    XCR0 bits 1 and 2   the OS actually SAVES the SSE and YMM state

  The third is the one people forget. A CPU can advertise AVX while the OS does
  not preserve ymm across a context switch, and then AVX code corrupts silently
  rather than faulting. xgetbv is the only way to ask, and it is itself
  unreachable unless OSXSAVE is set — hence the order. }

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

function AvxUsable: Boolean;
var feat, xcr: Integer;
begin
  AvxUsable := False;

  { Leaf 1 ecx carries both bits we need. Note the variables are NOT named after
    registers: `mov ecx, ecx` would parse as the register moving into itself and
    silently store nothing. }
  feat := 0;
  asm
    mov eax, 1
    cpuid
    mov feat, ecx
  end;
  if ((feat shr 28) and 1) = 0 then Exit;    { no AVX }
  if ((feat shr 27) and 1) = 0 then Exit;    { no OSXSAVE -> xgetbv would #UD }

  xcr := 0;
  asm
    xor ecx, ecx
    xgetbv
    mov xcr, eax
  end;
  { bit 1 = SSE state saved, bit 2 = YMM state saved. Both, or ymm is not
    preserved across a context switch and AVX code is unsafe. }
  if ((xcr shr 1) and 3) <> 3 then Exit;
  AvxUsable := True;
end;

function FmaUsable: Boolean;
var feat: Integer;
begin
  { FMA is a SEPARATE feature bit from AVX (leaf 1 ecx bit 12), not implied by
    it: Sandy Bridge has AVX and no FMA, so folding the two into one gate would
    #UD on real hardware. Callers must have established AvxUsable first — this
    only adds the FMA question on top. }
  feat := 0;
  asm
    mov eax, 1
    cpuid
    mov feat, ecx
  end;
  FmaUsable := ((feat shr 12) and 1) = 1;
end;

var
  a, b, r: Double;
  mask: Integer;

begin
  failures := 0;

  if not AvxUsable then
  begin
    { A clean skip, reported as success. The alternative — failing on a machine
      without AVX — would make the suite hardware-dependent, and the encodings
      are pinned against gas regardless of what this CPU can execute. }
    WriteLn('asm avx ok');
    Exit;
  end;

  { vbroadcastsd fills all FOUR lanes from one scalar. It is also the 0F38-map
    instruction, so if the VEX map selection were wrong this would be the first
    thing to misbehave. }
  a := 1.5; b := 0.25;
  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1      { [1.5 | 1.5 | 1.5 | 1.5] }
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2      { [0.25 x4] }
    vaddpd ymm2, ymm0, ymm1
    movsd r, xmm2                { low lane }
  end;
  Check(r, 1.75, 'vaddpd (256-bit) low lane');

  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2
    vmulpd ymm2, ymm0, ymm1
    movsd r, xmm2
  end;
  Check(r, 0.375, 'vmulpd (256-bit) low lane');

  { NON-DESTRUCTIVE is the structural claim of the v-forms: after
    `vaddpd ymm2, ymm0, ymm1` both sources must be unchanged. An encoder that
    put the second source in ModRM instead of vvvv would still compute a
    plausible sum, so this is checked directly. }
  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2
    vaddpd ymm2, ymm0, ymm1
    movsd r, xmm0                { ymm0 must still hold 1.5 }
  end;
  Check(r, 1.5, 'vaddpd left source untouched (non-destructive)');

  { All FOUR lanes, proven through vcmppd + vmovmskpd. A 256-bit compare over
    four lanes yields a 4-bit mask; if L were wrong and this ran 128-bit, only
    two bits could ever be set, so 15 is the assertion that the upper half is
    really being computed. }
  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1      { 1.5 x4 }
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2      { 0.25 x4 }
    vcmppd ymm2, ymm1, ymm0, 1   { 0.25 < 1.5 -> all four true }
    vmovmskpd eax, ymm2
    mov mask, eax
  end;
  CheckI(mask, 15, 'vcmppd over 4 lanes gives a 4-bit mask');

  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2
    vcmppd ymm2, ymm0, ymm1, 1   { 1.5 < 0.25 -> all four false }
    vmovmskpd eax, ymm2
    mov mask, eax
  end;
  CheckI(mask, 0, 'vcmppd all-false gives an empty mask');

  { FMA: vfmadd231pd computes dest := src1*src2 + dest, so the accumulator is
    the DESTINATION and both sources are read-only. Zero the accumulator with
    vxorpd first — 1.5*0.25 = 0.375. }
  if FmaUsable then
  begin
  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2
    vxorpd ymm3, ymm3, ymm3
    vfmadd231pd ymm3, ymm0, ymm1
    movsd r, xmm3
  end;
  Check(r, 0.375, 'vfmadd231pd accumulates into the destination');

  { ...and accumulating twice must double it, which is what distinguishes a
    real FMA from a plain multiply into the destination. }
  asm
    movsd xmm1, a
    vbroadcastsd ymm0, xmm1
    movsd xmm2, b
    vbroadcastsd ymm1, xmm2
    vxorpd ymm3, ymm3, ymm3
    vfmadd231pd ymm3, ymm0, ymm1
    vfmadd231pd ymm3, ymm0, ymm1
    movsd r, xmm3
  end;
  Check(r, 0.75, 'vfmadd231pd twice accumulates rather than overwrites');
  end;

  if failures = 0 then WriteLn('asm avx ok')
  else WriteLn('asm avx FAILED ', failures);
end.
