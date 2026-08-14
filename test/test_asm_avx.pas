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
  unreachable unless OSXSAVE is set — hence the order.

  AND A FOURTH, learned the hard way: `vbroadcastsd` exists in AVX1 only with a
  MEMORY source. The register-source form `vbroadcastsd ymm, xmm` was introduced
  with AVX2 (leaf 7 ebx bit 5), so a gate that checks AVX alone passes on an
  Ivy Bridge box and then #UDs on the first broadcast — which is exactly what
  happened on the watcher host. The arithmetic blocks below therefore broadcast
  from MEMORY, so the 256-bit coverage (L bit, four lanes, non-destructive
  sources, the 0F38 map) still runs everywhere AVX runs; the register-source
  form gets its own block behind Avx2Usable. }

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

function Avx2Usable: Boolean;
var feat, maxLeaf: Integer;
begin
  Avx2Usable := False;

  { Leaf 7 does not exist on every CPU that has AVX in principle, and asking for
    a leaf above the maximum returns the HIGHEST leaf's data instead of zeros —
    a wrong answer rather than a safe one. }
  maxLeaf := 0;
  asm
    mov eax, 0
    cpuid
    mov maxLeaf, eax
  end;
  if maxLeaf < 7 then Exit;

  { AVX2 is leaf 7 with SUBLEAF 0 — ecx must be zeroed before cpuid or the
    answer is some other subleaf's. Callers must have established AvxUsable
    first; this only adds the AVX2 question on top, the same shape as FmaUsable
    below. Needed by the REGISTER-source `vbroadcastsd ymm, xmm` only. }
  feat := 0;
  asm
    mov eax, 7
    xor ecx, ecx
    cpuid
    mov feat, ebx
  end;
  Avx2Usable := ((feat shr 5) and 1) = 1;
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
    vbroadcastsd ymm0, a         { [1.5 | 1.5 | 1.5 | 1.5] }
    vbroadcastsd ymm1, b         { [0.25 x4] }
    vaddpd ymm2, ymm0, ymm1
    movsd r, xmm2                { low lane }
  end;
  Check(r, 1.75, 'vaddpd (256-bit) low lane');

  asm
    vbroadcastsd ymm0, a
    vbroadcastsd ymm1, b
    vmulpd ymm2, ymm0, ymm1
    movsd r, xmm2
  end;
  Check(r, 0.375, 'vmulpd (256-bit) low lane');

  { NON-DESTRUCTIVE is the structural claim of the v-forms: after
    `vaddpd ymm2, ymm0, ymm1` both sources must be unchanged. An encoder that
    put the second source in ModRM instead of vvvv would still compute a
    plausible sum, so this is checked directly. }
  asm
    vbroadcastsd ymm0, a
    vbroadcastsd ymm1, b
    vaddpd ymm2, ymm0, ymm1
    movsd r, xmm0                { ymm0 must still hold 1.5 }
  end;
  Check(r, 1.5, 'vaddpd left source untouched (non-destructive)');

  { All FOUR lanes, proven through vcmppd + vmovmskpd. A 256-bit compare over
    four lanes yields a 4-bit mask; if L were wrong and this ran 128-bit, only
    two bits could ever be set, so 15 is the assertion that the upper half is
    really being computed. }
  asm
    vbroadcastsd ymm0, a         { 1.5 x4 }
    vbroadcastsd ymm1, b         { 0.25 x4 }
    vcmppd ymm2, ymm1, ymm0, 1   { 0.25 < 1.5 -> all four true }
    vmovmskpd eax, ymm2
    mov mask, eax
  end;
  CheckI(mask, 15, 'vcmppd over 4 lanes gives a 4-bit mask');

  asm
    vbroadcastsd ymm0, a
    vbroadcastsd ymm1, b
    vcmppd ymm2, ymm0, ymm1, 1   { 1.5 < 0.25 -> all four false }
    vmovmskpd eax, ymm2
    mov mask, eax
  end;
  CheckI(mask, 0, 'vcmppd all-false gives an empty mask');

  { The REGISTER-source broadcast, the one that needs AVX2. Same arithmetic as
    the first block, reached the other way — an xmm loaded by movsd, then
    splatted. Behind its own gate because this exact form is what #UDs on an
    Ivy Bridge box that answers yes to every AVX1 question. }
  if Avx2Usable then
  begin
    asm
      movsd xmm1, a
      vbroadcastsd ymm0, xmm1
      movsd xmm2, b
      vbroadcastsd ymm1, xmm2
      vaddpd ymm2, ymm0, ymm1
      movsd r, xmm2
    end;
    Check(r, 1.75, 'vbroadcastsd from a register (AVX2) feeds vaddpd');
  end;

  { FMA: vfmadd231pd computes dest := src1*src2 + dest, so the accumulator is
    the DESTINATION and both sources are read-only. Zero the accumulator with
    vxorpd first — 1.5*0.25 = 0.375. }
  if FmaUsable then
  begin
  asm
    vbroadcastsd ymm0, a
    vbroadcastsd ymm1, b
    vxorpd ymm3, ymm3, ymm3
    vfmadd231pd ymm3, ymm0, ymm1
    movsd r, xmm3
  end;
  Check(r, 0.375, 'vfmadd231pd accumulates into the destination');

  { ...and accumulating twice must double it, which is what distinguishes a
    real FMA from a plain multiply into the destination. }
  asm
    vbroadcastsd ymm0, a
    vbroadcastsd ymm1, b
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
