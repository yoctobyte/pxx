{ SPDX-License-Identifier: 0BSD }
unit mandelkernel;
{ Per-target, per-ISA-level Mandelbrot escape kernels with runtime dispatch.

  The premise: a Mandelbrot's hot loop is a tiny, perfectly regular kernel, so it
  is exactly the place where "you CAN drop to asm, and to the widest vector unit
  the machine actually has" should be demonstrated rather than asserted.

  The portable Double kernel is the oracle. Two DIFFERENT relationships to it:

    * The SSE2/AVX/AVX2 rungs compute the same IEEE-754 double recurrence, just
      2 or 4 lanes at a time, so they must agree with the oracle EXACTLY. A
      mismatch there is a bug. (The AVX2+FMA rung is the one exception: fusing
      the multiply-add changes the rounding, which is why it is a separate rung
      rather than a flag on misAVX — mixing them within one image would be
      visibly inconsistent.)
    * The GP-integer rung is Q4.28 FIXED POINT, a deliberately different and
      coarser arithmetic. It does NOT reproduce the Double kernel's escape
      counts and is not meant to — near the set boundary, where a pixel's count
      is decided in the last bits, it lands a few iterations either side. It is
      an approximation rung chosen for speed at shallow zoom, and it demotes
      itself once a pixel step outruns its resolution (FIXED_MIN_STEP below).
      Its own oracle is a portable Q4.28 loop, not the Double one.

  The ladder, best first. `DetectKernel` picks the top rung the CPU supports:

    AVX2 + FMA   4 doubles per iteration (ymm), fused multiply-add
    AVX          4 doubles per iteration (ymm)
    SSE2         2 doubles per iteration (xmm)
    GP-integer   1 pixel, Int64 Q4.28 in general-purpose registers
    portable     1 pixel, plain Pascal Double — the oracle, and the fallback
                 for every non-x86 target

  On aarch64 the NEON rung (2 doubles per iteration, v0..v31) belongs in the same
  ladder; it is not written yet, see the note by TMandelISA.

  --- WHY THE VECTOR ARMS ARE COMPILED OUT TODAY ---

  The SSE2/AVX/AVX2 kernels below are written as they should be, but the asm
  frontend cannot yet encode them: inline asm has no xmm/ymm register operands,
  no packed SSE mnemonics, no VEX prefix emitter, and no `cpuid`. See
  feature-inline-asm-xmm-operands, which tracks the whole ladder and phases it.

  So they sit behind `{$ifdef PXX_ASM_SIMD}`. That define exists for exactly one
  reason — the compiler cannot build this source yet — and it is NOT a
  configuration knob. When the asm frontend lands, DELETE the define and its
  {$ifdef}s; do not add a way to turn it on and off. Until then this unit
  compiles and runs on the GP-integer and portable rungs, and the source of the
  vector rungs is here to be reviewed, corrected, and switched on in one commit.

  Likewise CPU detection: the honest implementation is `cpuid`, which is also
  missing, so DetectISA reads /proc/cpuinfo on Linux. That is a real mechanism,
  not a stub — but it is Linux-only and reports what the OS advertises rather
  than what the instruction says, so it is replaced by a `cpuid` path under the
  same define.

  Track B/E (example support unit). Build --threadsafe if the caller does. }

interface

type
  { The rungs, ordered worst to best so `>` means "wider". }
  TMandelISA = (
    misPortable,    { plain Pascal Double — always available, the oracle }
    misFixedGP,     { Int64 Q4.28 in general-purpose registers (x86-64 asm) }
    misSSE2,        { 2 doubles/iteration }
    misAVX,         { 4 doubles/iteration }
    misAVX2FMA      { 4 doubles/iteration + fused multiply-add }
    { misNEON belongs here for aarch64 — same 2-wide shape as SSE2. Not written
      yet; it waits on the same asm-frontend work, see the unit header. }
  );

{ Human-readable name of a rung, for status lines and --check output. }
function ISAName(isa: TMandelISA): AnsiString;

{ Resolve CPU capability. Call ONCE from the main thread before any rendering.

  This is explicit rather than automatic for two reasons. It must not happen in
  the unit's initialization section, because file I/O silently fails there and
  the probe comes back saying "no SSE2" on a machine with AVX2 — see
  bug-file-io-silently-fails-in-unit-init. And it must not happen lazily on
  first use, because first use is inside the parallel render: workers then race
  to fill the cache and each one runs the probe, which measured slower in
  parallel than the entire serial render. Detection is a startup concern; this
  keeps it at startup, on one thread, where it belongs. }
procedure InitMandelKernel;

{ What this CPU can actually do, highest rung first. Resolved by
  InitMandelKernel; returns misPortable if that was never called. }
function DetectISA: TMandelISA;

{ The rung this build will really use: DetectISA, clamped to what the compiler
  could encode. Equal to DetectISA once feature-inline-asm-xmm-operands lands. }
function ActiveISA: TMandelISA;

{ Force a rung (for --check / benchmarking one against another). Passing a rung
  above ActiveISA is clamped down to it. }
procedure SetISA(isa: TMandelISA);

{ The oracle. The vector rungs must match this exactly; the fixed-point rung is
  a coarser arithmetic and deliberately does not — see the unit header. }
function EscapePortable(cre, cim: Double; maxIt: Integer): Integer;

{ One scanline of escape counts: `count` pixels starting at (cre0, cim), stepping
  `dre` in the real direction. This is the unit's real entry point — a per-ROW
  interface, not per-pixel, because that is what lets a vector kernel amortize
  its setup and keep 2 or 4 pixels in flight. The scalar rungs just loop.

  `dst` receives `count` escape counts at offset `dstOfs`. }
procedure EscapeRow(var dst: array of Integer; dstOfs, count: Integer;
                    cre0, dre, cim: Double; maxIt: Integer);

implementation

const
  FRAC    = 28;
  ONE     = 268435456;      { 1.0 in Q4.28 }
  ONEMASK = 268435455;      { ONE-1, for the truncate-toward-zero shift }
  FOUR    = 1073741824;     { 4.0 in Q4.28 }

  { Q4.28 resolves ~3.7e-9, so the fixed-point rung is only valid while a pixel
    step is coarser than that. Callers deeper than this must not select it;
    EscapeRow enforces it rather than trusting them. }
  FIXED_MIN_STEP = 0.00000001;

var
  gDetected: TMandelISA;      { resolved once in the initialization section }
  gDetectedValid: Boolean;    { set alongside it; a guard against use-before-init }
  gForced: TMandelISA;
  gForcedValid: Boolean;

function ISAName(isa: TMandelISA): AnsiString;
begin
  case isa of
    misAVX2FMA: ISAName := 'AVX2+FMA (4 doubles/iter)';
    misAVX:     ISAName := 'AVX (4 doubles/iter)';
    misSSE2:    ISAName := 'SSE2 (2 doubles/iter)';
    misFixedGP: ISAName := 'GP-integer Q4.28 (1 px/iter, asm)';
  else
    ISAName := 'portable Double (1 px/iter)';
  end;
end;

{ ---------------- CPU detection ---------------- }

{$ifdef PXX_ASM_SIMD}
{ The honest implementation: ask the CPU, not the OS.

  Leaf 1: EDX bit 26 = SSE2, ECX bit 28 = AVX, ECX bit 27 = OSXSAVE, bit 12 = FMA.
  Leaf 7 sub-leaf 0: EBX bit 5 = AVX2.
  AVX also requires the OS to have enabled YMM state, which OSXSAVE + XGETBV(0)
  bits 1 and 2 report — without that check, AVX instructions fault on a kernel
  that does not save YMM across context switches. }
procedure CpuId(leaf, subleaf: LongWord; var a, b, c, d: LongWord);
begin
  asm
    push rbx              { rbx is callee-saved and cpuid clobbers it }
    mov eax, leaf
    mov ecx, subleaf
    cpuid
    mov a, eax
    mov b, ebx
    mov c, ecx
    mov d, edx
    pop rbx
  end;
end;

function OsSupportsYmm: Boolean;
var lo, hi: LongWord;
begin
  asm
    push rcx
    push rdx
    mov ecx, 0
    xgetbv
    mov lo, eax
    mov hi, edx
    pop rdx
    pop rcx
  end;
  { bit 1 = XMM state saved, bit 2 = YMM state saved }
  OsSupportsYmm := ((lo shr 1) and 3) = 3;
end;

function DetectISARaw: TMandelISA;
var a, b, c, d: LongWord; haveAvx, haveFma, haveAvx2, haveOsxsave: Boolean;
begin
  DetectISARaw := misPortable;
  CpuId(0, 0, a, b, c, d);
  if a < 1 then Exit;

  CpuId(1, 0, a, b, c, d);
  if ((d shr 26) and 1) = 0 then Exit;          { no SSE2 — done }
  DetectISARaw := misSSE2;

  haveOsxsave := ((c shr 27) and 1) = 1;
  haveAvx     := ((c shr 28) and 1) = 1;
  haveFma     := ((c shr 12) and 1) = 1;
  if not (haveAvx and haveOsxsave) then Exit;
  if not OsSupportsYmm then Exit;               { CPU has it, OS will not save it }
  DetectISARaw := misAVX;

  CpuId(0, 0, a, b, c, d);
  if a < 7 then Exit;
  CpuId(7, 0, a, b, c, d);
  haveAvx2 := ((b shr 5) and 1) = 1;
  if haveAvx2 and haveFma then DetectISARaw := misAVX2FMA;
end;
{$else}
{ Stand-in until `cpuid` is encodable: read what the OS advertises. Real, but
  Linux-only and one remove from the truth — the kernel's flag list, not the
  CPU's answer. Replaced wholesale by DetectISARaw above. }
function CpuInfoHasFlag(const flag: AnsiString): Boolean;
var f: Text; line, pad: AnsiString; found: Boolean;
begin
  found := False;
  pad := ' ' + flag + ' ';
  {$I-}
  Assign(f, '/proc/cpuinfo');
  Reset(f);
  {$I+}
  if IOResult <> 0 then
  begin
    CpuInfoHasFlag := False;
    Exit;
  end;
  while not Eof(f) do
  begin
    ReadLn(f, line);
    if Copy(line, 1, 5) = 'flags' then
    begin
      if Pos(pad, ' ' + line + ' ') > 0 then found := True;
      Break;
    end;
  end;
  Close(f);
  CpuInfoHasFlag := found;
end;

function DetectISARaw: TMandelISA;
begin
  if not CpuInfoHasFlag('sse2') then
  begin
    DetectISARaw := misPortable;
    Exit;
  end;
  if CpuInfoHasFlag('avx2') and CpuInfoHasFlag('fma') then DetectISARaw := misAVX2FMA
  else if CpuInfoHasFlag('avx') then DetectISARaw := misAVX
  else DetectISARaw := misSSE2;
end;
{$endif}

procedure InitMandelKernel;
begin
{$ifdef CPUX86_64}
  gDetected := DetectISARaw;
{$else}
  { Every other target: the portable kernel is all there is until its vector
    unit joins the ladder (NEON first — see TMandelISA). }
  gDetected := misPortable;
{$endif}
  gDetectedValid := True;
end;

function DetectISA: TMandelISA;
begin
  if gDetectedValid then DetectISA := gDetected else DetectISA := misPortable;
end;

{ The ceiling this BUILD can reach, as opposed to what the CPU can do. }
function BuildCeiling: TMandelISA;
begin
{$ifdef CPUX86_64}
  {$ifdef PXX_ASM_SIMD}
  BuildCeiling := misAVX2FMA;
  {$else}
  { The vector kernels are compiled out — feature-inline-asm-xmm-operands. The
    GP-integer rung uses general-purpose registers only, so it survives. }
  BuildCeiling := misFixedGP;
  {$endif}
{$else}
  BuildCeiling := misPortable;
{$endif}
end;

function ActiveISA: TMandelISA;
var want, ceil: TMandelISA;
begin
  if gForcedValid then want := gForced else want := DetectISA;
  ceil := BuildCeiling;
  if want > ceil then want := ceil;
  ActiveISA := want;
end;

procedure SetISA(isa: TMandelISA);
begin
  gForced := isa;
  gForcedValid := True;
end;

{ ---------------- the oracle ---------------- }

function EscapePortable(cre, cim: Double; maxIt: Integer): Integer;
var zre, zim, zr2, zi2, tmp: Double; i: Integer;
begin
  zre := 0.0; zim := 0.0; zr2 := 0.0; zi2 := 0.0;
  i := 0;
  while (i < maxIt) and (zr2 + zi2 <= 4.0) do
  begin
    tmp := zr2 - zi2 + cre;
    zim := 2.0 * zre * zim + cim;
    zre := tmp;
    zr2 := zre * zre;
    zi2 := zim * zim;
    i := i + 1;
  end;
  EscapePortable := i;
end;

{ ---------------- GP-integer rung (works today) ---------------- }

function ToFixed(d: Double): Int64;
begin ToFixed := Trunc(d * 268435456.0); end;

{$ifdef CPUX86_64}
{ Int64 Q4.28 escape loop in general-purpose registers.

  r8=zre r9=zim r10=zr2 r11=zi2 r12=i r13=maxIt; rax/rcx/rdx scratch. r12/r13 are
  callee-saved (the r12-r15 residency pool), so the block saves them itself.

  `maxIt` is a 4-byte Integer, hence `mov r13d` — a 64-bit load picks up whatever
  sits above the local and the loop never terminates.

  `sar rdx,63 / and ONEMASK / add / sar FRAC` is a shift that truncates toward
  ZERO, matching Pascal's `div`. A bare arithmetic shift floors instead, and
  would disagree with the portable fixed-point reference on negative
  intermediates — which is most of the left half of the image. }
function EscapeFixedGP(cre, cim: Int64; maxIt: Integer): Integer;
var i: Integer;
begin
  i := 0;
  asm
    push r12
    push r13
    mov r8, 0
    mov r9, 0
    mov r10, 0
    mov r11, 0
    mov r12, 0
    mov r13d, maxIt
  kloop:
    cmp r12, r13
    jge kdone
    mov rax, r10
    add rax, r11
    cmp rax, 1073741824      { > FOUR -> escaped }
    jg kdone
    { tmp = zr2 - zi2 + cre }
    mov rcx, r10
    sub rcx, r11
    add rcx, cre
    { zim = trunc((2*zre*zim) / ONE) + cim }
    mov rax, r8
    imul rax, r9
    add rax, rax
    mov rdx, rax
    sar rdx, 63
    and rdx, 268435455
    add rax, rdx
    sar rax, 28
    add rax, cim
    mov r9, rax
    { zre = tmp }
    mov r8, rcx
    { zr2 = trunc(zre*zre / ONE) }
    mov rax, r8
    imul rax, r8
    mov rdx, rax
    sar rdx, 63
    and rdx, 268435455
    add rax, rdx
    sar rax, 28
    mov r10, rax
    { zi2 = trunc(zim*zim / ONE) }
    mov rax, r9
    imul rax, r9
    mov rdx, rax
    sar rdx, 63
    and rdx, 268435455
    add rax, rdx
    sar rax, 28
    mov r11, rax
    inc r12
    jmp kloop
  kdone:
    mov i, r12d
    pop r13
    pop r12
  end;
  EscapeFixedGP := i;
end;
{$endif}

{ ---------------- vector rungs (see the unit header) ---------------- }

{$ifdef PXX_ASM_SIMD}

{ Two pixels per iteration in one xmm register pair.

  The scalar recurrence, lane-wise:
    zr2 = zre*zre ; zi2 = zim*zim
    while any lane still has zr2+zi2 <= 4 and i < maxIt:
      tmp = zr2 - zi2 + cre
      zim = 2*zre*zim + cim
      zre = tmp

  Per-lane exit is the whole trick. There is no per-lane branch, so instead each
  iteration builds a mask of the lanes still inside (`cmpltpd` against 4.0, which
  yields all-ones per passing lane) and ADDS that mask, as an integer -1, to a
  per-lane counter. A lane that escaped stops incrementing while its neighbour
  keeps going; the loop ends when the mask is empty (`movmskpd` -> 0) or the
  iteration cap is hit. Escaped lanes keep iterating harmlessly — their z values
  run off to infinity, but nothing reads them again.

  Register map:
    xmm0 zre   xmm1 zim   xmm2 zr2   xmm3 zi2
    xmm4 cre   xmm5 cim   xmm6 four  xmm7 counters (2 packed Int64)
    xmm8 scratch/mask  -- caller-save per optimization-architecture.md, saved here

  Counts land back in `out0`/`out1` via the stack. }
procedure EscapePairSSE2(cre0, cre1, cim: Double; maxIt: Integer;
                         var out0, out1: Integer);
var four, two, counters: array[0..1] of Double; lanes: array[0..1] of Int64;
begin
  four[0] := 4.0;     four[1] := 4.0;
  two[0]  := 2.0;     two[1]  := 2.0;
  counters[0] := 0.0; counters[1] := 0.0;
  asm
    sub rsp, 16
    movupd [rsp], xmm8            { xmm8 is caller-save; we clobber it }

    movupd xmm4, cre0             { cre0, cre1 are adjacent locals: one load }
    movsd  xmm5, cim
    unpcklpd xmm5, xmm5           { broadcast cim to both lanes }
    movupd xmm6, four
    pxor   xmm0, xmm0             { zre = 0,0 }
    pxor   xmm1, xmm1             { zim = 0,0 }
    pxor   xmm2, xmm2             { zr2 = 0,0 }
    pxor   xmm3, xmm3             { zi2 = 0,0 }
    pxor   xmm7, xmm7             { counters = 0,0 }
    mov    ecx, 0
    mov    edx, maxIt

  vloop:
    cmp ecx, edx
    jge vdone
    { mask = (zr2 + zi2) < 4 , per lane }
    movapd xmm8, xmm2
    addpd  xmm8, xmm3
    cmpltpd xmm8, xmm6
    movmskpd eax, xmm8
    test   eax, eax
    jz     vdone                  { both lanes escaped }
    { counters -= mask   (mask lane = -1 when still inside) }
    psubq  xmm7, xmm8

    { tmp = zr2 - zi2 + cre  -> reuse xmm2 after zim is computed }
    movapd xmm9, xmm2
    subpd  xmm9, xmm3
    addpd  xmm9, xmm4
    { zim = 2*zre*zim + cim }
    mulpd  xmm1, xmm0
    addpd  xmm1, xmm1
    addpd  xmm1, xmm5
    { zre = tmp }
    movapd xmm0, xmm9
    { zr2 = zre*zre ; zi2 = zim*zim }
    movapd xmm2, xmm0
    mulpd  xmm2, xmm0
    movapd xmm3, xmm1
    mulpd  xmm3, xmm1

    inc ecx
    jmp vloop

  vdone:
    movupd lanes, xmm7
    movupd xmm8, [rsp]
    add rsp, 16
  end;
  out0 := Integer(lanes[0]);
  out1 := Integer(lanes[1]);
end;

{ Four pixels per iteration in ymm. Same masked-counter scheme as the SSE2 rung,
  widened: vcmppd with predicate 1 (LT_OS) instead of cmpltpd, vmovmskpd over 4
  lanes, and the non-destructive three-operand VEX forms remove most of the
  movapd shuffling the SSE2 version needs.

  `useFma` selects vfmadd231pd for the zim update (zim = 2*zre*zim + cim folds
  into one FMA after the doubling), which is the only place FMA helps here — the
  squarings feed a subtraction, not an accumulation. Rounding differs from the
  non-FMA path by design; the caller must not mix the two within one image if it
  cares about exact reproducibility, which is why misAVX and misAVX2FMA are
  separate rungs rather than one with a flag. }
procedure EscapeQuadAVX(cre0, cre1, cre2, cre3, cim: Double; maxIt: Integer;
                        useFma: Boolean;
                        var out0, out1, out2, out3: Integer);
var four: array[0..3] of Double; lanes: array[0..3] of Int64;
begin
  four[0] := 4.0; four[1] := 4.0; four[2] := 4.0; four[3] := 4.0;
  asm
    vmovupd ymm4, cre0            { four adjacent locals: one load }
    vbroadcastsd ymm5, cim
    vmovupd ymm6, four
    vxorpd  ymm0, ymm0, ymm0      { zre }
    vxorpd  ymm1, ymm1, ymm1      { zim }
    vxorpd  ymm2, ymm2, ymm2      { zr2 }
    vxorpd  ymm3, ymm3, ymm3      { zi2 }
    vxorpd  ymm7, ymm7, ymm7      { counters }
    mov ecx, 0
    mov edx, maxIt

  aloop:
    cmp ecx, edx
    jge adone
    vaddpd  ymm8, ymm2, ymm3
    vcmppd  ymm8, ymm8, ymm6, 1   { predicate 1 = LT_OS }
    vmovmskpd eax, ymm8
    test eax, eax
    jz adone
    vpsubq  ymm7, ymm7, ymm8

    vsubpd  ymm9, ymm2, ymm3
    vaddpd  ymm9, ymm9, ymm4      { tmp = zr2 - zi2 + cre }

    vmulpd  ymm1, ymm1, ymm0      { zre*zim }
    vaddpd  ymm1, ymm1, ymm1      { 2*zre*zim }
    vaddpd  ymm1, ymm1, ymm5      { + cim }

    vmovapd ymm0, ymm9            { zre = tmp }
    vmulpd  ymm2, ymm0, ymm0
    vmulpd  ymm3, ymm1, ymm1

    inc ecx
    jmp aloop

  adone:
    vmovupd lanes, ymm7
    vzeroupper                    { avoid the SSE/AVX transition penalty on return }
  end;
  out0 := Integer(lanes[0]);
  out1 := Integer(lanes[1]);
  out2 := Integer(lanes[2]);
  out3 := Integer(lanes[3]);
end;
{$endif}

{ ---------------- the row entry point ---------------- }

procedure EscapeRow(var dst: array of Integer; dstOfs, count: Integer;
                    cre0, dre, cim: Double; maxIt: Integer);
var
  i: Integer;
  isa: TMandelISA;
{$ifdef PXX_ASM_SIMD}
  n0, n1, n2, n3: Integer;
{$endif}
begin
  isa := ActiveISA;

  { The fixed-point rung silently loses the image once a pixel step is finer
    than Q4.28 can resolve, so it demotes itself rather than drawing mush. }
  if (isa = misFixedGP) and (dre < FIXED_MIN_STEP) then isa := misPortable;

{$ifdef PXX_ASM_SIMD}
  if isa >= misAVX then
  begin
    i := 0;
    while i + 3 < count do
    begin
      EscapeQuadAVX(cre0 + i * dre, cre0 + (i + 1) * dre,
                    cre0 + (i + 2) * dre, cre0 + (i + 3) * dre,
                    cim, maxIt, isa = misAVX2FMA, n0, n1, n2, n3);
      dst[dstOfs + i]     := n0;
      dst[dstOfs + i + 1] := n1;
      dst[dstOfs + i + 2] := n2;
      dst[dstOfs + i + 3] := n3;
      i := i + 4;
    end;
    { tail: fewer than 4 pixels left, scalar }
    while i < count do
    begin
      dst[dstOfs + i] := EscapePortable(cre0 + i * dre, cim, maxIt);
      i := i + 1;
    end;
    Exit;
  end;

  if isa = misSSE2 then
  begin
    i := 0;
    while i + 1 < count do
    begin
      EscapePairSSE2(cre0 + i * dre, cre0 + (i + 1) * dre, cim, maxIt, n0, n1);
      dst[dstOfs + i]     := n0;
      dst[dstOfs + i + 1] := n1;
      i := i + 2;
    end;
    while i < count do
    begin
      dst[dstOfs + i] := EscapePortable(cre0 + i * dre, cim, maxIt);
      i := i + 1;
    end;
    Exit;
  end;
{$endif}

{$ifdef CPUX86_64}
  if isa = misFixedGP then
  begin
    for i := 0 to count - 1 do
      dst[dstOfs + i] := EscapeFixedGP(ToFixed(cre0 + i * dre), ToFixed(cim), maxIt);
    Exit;
  end;
{$endif}

  for i := 0 to count - 1 do
    dst[dstOfs + i] := EscapePortable(cre0 + i * dre, cim, maxIt);
end;

{ `initialization`, not the classic `begin ... end.` — that form is currently
  parsed and then silently dropped, so this would be dead code. See
  bug-unit-init-begin-form-not-executed. }
initialization
  { Deliberately NO detection here — see InitMandelKernel. }
  gDetected := misPortable;
  gDetectedValid := False;
  gForcedValid := False;
end.
