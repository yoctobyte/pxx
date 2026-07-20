{ SPDX-License-Identifier: 0BSD }
program MandelZoom;
{ Real-time auto-zooming Mandelbrot for the terminal — the ANIMATED sibling of
  examples/mandelbrot/mandelbrot.pas (which stays the deterministic checksum
  oracle and is not touched here).

  What it shows off, in one screen:
    * parallel(pdOnDemand) scanlines — deep zooms have wildly uneven per-row
      cost (in-set rows burn all MAXIT, escape rows exit early), which is
      exactly where work stealing beats a contiguous split.
    * an INLINE-ASM iteration kernel (x86-64), proven equal to the portable
      Pascal kernel over a test grid before it is trusted.
    * double buffering — the next frame is composed into a string off-screen and
      swapped in with a single write, so there is no tearing.
    * palette rotation — the colour LUT index is offset per frame, giving the
      classic shimmering bands for free (it never re-iterates a pixel).
    * optional rotation of the sampling basis, for a bit more motion.
    * half-block glyphs, so each character cell carries TWO pixels and the
      vertical resolution doubles.

  Unlike mandelbrot.pas this demo is explicitly NOT a cross-target oracle: the
  zoom path and palette are float and free to differ. It is allowed to be fast.

  --- kernels, and why the asm one is INTEGER ---

  The ticket asked for an SSE2 double-precision asm kernel. That cannot be
  written today: the Pascal inline-asm frontend has no XMM register operands
  (the encoders do — only `AsmRegLookup` in compiler/asmfront.inc is missing
  them). See feature-inline-asm-xmm-operands. So the asm kernel here is the
  Int64 Q4.28 fixed-point escape loop in general-purpose registers, which is a
  real showcase and works today.

  Q4.28 has ~3.7e-9 of resolution, so it runs out long before a deep zoom does.
  The demo therefore switches kernels automatically: fixed-point asm while the
  window is coarse enough to resolve, portable Double once it is not. The status
  line names the kernel in use each frame, so the handover is visible rather
  than hidden.

  Usage:
    mandelzoom                 animate until 'q' (or Ctrl-C)
    mandelzoom --frames N      render N frames then exit (bounded; for a look)
    mandelzoom --check         verify the asm kernel == the portable kernel, exit
    mandelzoom --no-rotate     skip the sampling-basis rotation
    mandelzoom --workers N     override the parallel-for worker count
    mandelzoom --fps N         frame-rate cap (default 30; 0 = as fast as it goes)

  Track B/E (example app). Build --threadsafe. }

uses sysutils, baseunix, ansiterm, palparallel;

const
  FRAC     = 28;
  ONE      = 268435456;      { 1.0 in Q4.28 }
  ONEMASK  = 268435455;      { ONE-1, for the truncate-toward-zero shift }
  FOUR     = 1073741824;     { 4.0 in Q4.28 — escape radius squared }

  MAXIT_MIN = 120;
  MAXIT_MAX = 900;

  { Below this span the Q4.28 kernel can no longer resolve one pixel, so the
    demo hands over to the portable Double kernel. }
  FIXED_SPAN_FLOOR = 0.00002;

  PALSIZE = 256;

  DEFAULT_FPS = 30;

type
  { Named type: a parallel-for captures an aggregate only if its type has a name. }
  TPixels = array of Integer;

  TTarget = record
    re, im: Double;
    depth:  Double;      { final span_re to zoom down to }
    name:   AnsiString;
  end;

const
  TARGETCOUNT = 4;

{ ---------------- kernels ---------------- }

{ Portable Double escape-time loop — the correctness reference and the deep-zoom
  workhorse. Same recurrence as mandelbrot.pas. }
function EscapeFloat(cre, cim: Double; max_it: Integer): Integer;
var zre, zim, zr2, zi2, tmp: Double; i: Integer;
begin
  zre := 0.0; zim := 0.0; zr2 := 0.0; zi2 := 0.0;
  i := 0;
  while (i < max_it) and (zr2 + zi2 <= 4.0) do
  begin
    tmp := zr2 - zi2 + cre;
    zim := 2.0 * zre * zim + cim;
    zre := tmp;
    zr2 := zre * zre;
    zi2 := zim * zim;
    i := i + 1;
  end;
  EscapeFloat := i;
end;

{ Portable Q4.28 fixed-point loop — the oracle the asm kernel is checked
  against. `div ONE` truncates toward zero (Pascal semantics), which is what the
  asm kernel reproduces with its sign-correcting shift. }
function EscapeFixed(cre, cim: Int64; max_it: Integer): Integer;
var zre, zim, zr2, zi2, tmp: Int64; i: Integer;
begin
  zre := 0; zim := 0; zr2 := 0; zi2 := 0;
  i := 0;
  while (i < max_it) and (zr2 + zi2 <= FOUR) do
  begin
    tmp := zr2 - zi2 + cre;
    zim := ((2 * zre * zim) div ONE) + cim;
    zre := tmp;
    zr2 := (zre * zre) div ONE;
    zi2 := (zim * zim) div ONE;
    i := i + 1;
  end;
  EscapeFixed := i;
end;

{$ifdef CPUX86_64}
{ Inline-asm Q4.28 kernel (x86-64, general-purpose registers only).

  Register map: r8=zre r9=zim r10=zr2 r11=zi2 r12=i r13=max_it, rax/rcx/rdx
  scratch. r12/r13 are callee-saved (the r12-r15 residency/scratch pool), so the
  block saves and restores them itself.

  `max_it` is a 4-byte Integer, hence `mov r13d` — loading it with a 64-bit `mov`
  picks up whatever sits above the local and the loop never terminates.

  The `sar rdx,63 / and ONEMASK / add / sar FRAC` sequence is a shift that
  truncates toward zero, matching Pascal's `div`; a bare arithmetic shift would
  floor and disagree with EscapeFixed on negative intermediates. }
function EscapeFixedAsm(cre, cim: Int64; max_it: Integer): Integer;
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
    mov r13d, max_it
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
  EscapeFixedAsm := i;
end;

function HaveAsmKernel: Boolean;
begin HaveAsmKernel := True; end;
{$else}
{ No asm kernel for this target yet — the portable fixed-point loop stands in,
  so every path below still works, it is just not the showcase. }
function EscapeFixedAsm(cre, cim: Int64; max_it: Integer): Integer;
begin EscapeFixedAsm := EscapeFixed(cre, cim, max_it); end;

function HaveAsmKernel: Boolean;
begin HaveAsmKernel := False; end;
{$endif}

function ToFixed(d: Double): Int64;
begin ToFixed := Trunc(d * 268435456.0); end;

{ ---------------- the asm-vs-portable oracle ---------------- }

{ Trust nothing: before the asm kernel renders a single frame, prove it agrees
  with the portable fixed-point kernel over a grid that covers in-set, escaping
  and negative-coordinate pixels. Returns the mismatch count. }
function CheckAsmKernel(var checked: Integer): Integer;
var x, y, bad, a, b: Integer; cr, ci: Int64;
begin
  bad := 0; checked := 0;
  for y := 0 to 60 do
    for x := 0 to 90 do
    begin
      cr := ToFixed(-2.5 + (x / 90.0) * 3.5);
      ci := ToFixed(-1.25 + (y / 60.0) * 2.5);
      a := EscapeFixedAsm(cr, ci, 300);
      b := EscapeFixed(cr, ci, 300);
      checked := checked + 1;
      if a <> b then bad := bad + 1;
    end;
  CheckAsmKernel := bad;
end;

{ ---------------- palette ---------------- }

var
  palR, palG, palB: array[0..PALSIZE - 1] of Integer;

{ A smooth cyclic ramp — three phase-shifted cosine-ish lobes built from integer
  triangles, so the LUT is cheap and wraps seamlessly (a rotating palette must
  have no seam or the animation flickers once per revolution). }
function Lobe(t, phase: Integer): Integer;
var u, v: Integer;
begin
  u := (t + phase) mod PALSIZE;
  if u < PALSIZE div 2 then v := u * 2 else v := (PALSIZE - u) * 2 - 1;
  { v in [0..255]; square it for a gentler dark end }
  Lobe := (v * v) div 255;
end;

procedure BuildPalette;
var i: Integer;
begin
  for i := 0 to PALSIZE - 1 do
  begin
    palR[i] := Lobe(i, 0);
    palG[i] := Lobe(i, PALSIZE div 3);
    palB[i] := Lobe(i, (2 * PALSIZE) div 3);
  end;
end;

{ ---------------- render ---------------- }

{ Render state the workers read. These are GLOBALS on purpose: a parallel-for
  does not capture globals (they are statically addressable, so every worker
  reaches them directly), and the capture path currently mishandles a captured
  Boolean and a captured dynamic array passed on to a callee — see
  bug-parallel-for-captured-boolean-loses-type and
  bug-parallel-for-captured-dynarray-var-arg-segfault. They are written once by
  the main loop before the render and only read by workers, so there is no race.
  fb is partitioned by row, so no two workers ever touch the same element. }
var
  fb: TPixels;
  gW, gH, gMaxIt: Integer;
  gCx, gCy, gSpanRe, gSpanIm, gCosA, gSinA: Double;
  gUseFixed: Boolean;

{ One scanline of escape counts into fb. A PROCEDURE, so all its scratch is on
  the calling worker's own stack; it writes only row `row` of fb. }
procedure RenderRow(row: Integer);
var col, n: Integer; dx, dy, rx, ry, cre, cim: Double;
begin
  dy := (row / (gH - 1)) - 0.5;
  for col := 0 to gW - 1 do
  begin
    dx := (col / (gW - 1)) - 0.5;
    { rotate the sampling basis; gCosA=1/gSinA=0 when rotation is off }
    rx := dx * gCosA - dy * gSinA;
    ry := dx * gSinA + dy * gCosA;
    cre := gCx + rx * gSpanRe;
    cim := gCy + ry * gSpanIm;
    if gUseFixed then
      n := EscapeFixedAsm(ToFixed(cre), ToFixed(cim), gMaxIt)
    else
      n := EscapeFloat(cre, cim, gMaxIt);
    fb[row * gW + col] := n;
  end;
end;

{ Render the whole frame from the global state above.

  pdOnDemand is the point of the demo: at depth some rows sit entirely inside
  the set and burn all MAXIT while their neighbours escape in a handful of
  iterations, so a contiguous split would leave most workers idle. }
procedure RenderFrame;
var row: Integer;
begin
  parallel(pdOnDemand) for row := 0 to gH - 1 do RenderRow(row);
end;

{ ---------------- compose ---------------- }

function IntStr(v: Integer): AnsiString;
begin IntStr := IntToStr(v); end;

{ Map an escape count to a palette index; in-set pixels are black. `shift` is
  the per-frame palette rotation. }
procedure ColorOf(n, maxIt, shift: Integer; var r, g, b: Integer);
var idx: Integer;
begin
  if n >= maxIt then begin r := 0; g := 0; b := 0; Exit; end;
  idx := ((n * 3) + shift) mod PALSIZE;
  r := palR[idx]; g := palG[idx]; b := palB[idx];
end;

{ Compose the frame into ONE string: half-block glyphs (upper pixel as the
  foreground of U+2580, lower pixel as the background), emitting an SGR sequence
  only when a colour actually changes. Returned whole so the caller can swap it
  in with a single write — that is the double-buffer swap. }
function ComposeFrame(w, cols, rows, maxIt, shift: Integer): AnsiString;
var
  cy, cx, ur, ug, ub, lr, lg, lb: Integer;
  pur, pug, pub, plr, plg, plb: Integer;
  s, line: AnsiString;
begin
  s := AnsiMove(1, 1);
  for cy := 0 to rows - 1 do
  begin
    line := '';
    pur := -1; pug := -1; pub := -1;
    plr := -1; plg := -1; plb := -1;
    for cx := 0 to cols - 1 do
    begin
      ColorOf(fb[(cy * 2) * w + cx], maxIt, shift, ur, ug, ub);
      ColorOf(fb[(cy * 2 + 1) * w + cx], maxIt, shift, lr, lg, lb);
      if (ur <> pur) or (ug <> pug) or (ub <> pub) then
      begin
        line := line + #27'[38;2;' + IntStr(ur) + ';' + IntStr(ug) + ';' + IntStr(ub) + 'm';
        pur := ur; pug := ug; pub := ub;
      end;
      if (lr <> plr) or (lg <> plg) or (lb <> plb) then
      begin
        line := line + AnsiBgRGB(lr, lg, lb);
        plr := lr; plg := lg; plb := lb;
      end;
      line := line + #$E2#$96#$80;    { U+2580 UPPER HALF BLOCK }
    end;
    s := s + line + AnsiReset + #10;
  end;
  ComposeFrame := s;
end;

{ ---------------- zoom path ---------------- }

var
  targets: array[0..TARGETCOUNT - 1] of TTarget;

procedure InitTargets;
begin
  targets[0].re := -0.743643887037; targets[0].im := 0.131825904205;
  targets[0].depth := 0.0000004;    targets[0].name := 'seahorse valley';
  targets[1].re := -1.250660;       targets[1].im := 0.020120;
  targets[1].depth := 0.0000020;    targets[1].name := 'minibrot';
  targets[2].re := -0.10109636384;  targets[2].im := 0.95628651080;
  targets[2].depth := 0.0000010;    targets[2].name := 'Misiurewicz point';
  targets[3].re :=  0.360240443437; targets[3].im := 0.641313061064;
  targets[3].depth := 0.0000015;    targets[3].name := 'spiral';
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

{ Cheap cos/sin for the basis rotation — a 4th-order Taylor pair folded into
  [-pi,pi]. Accuracy is irrelevant here (it only spins the image), and it keeps
  the demo free of a math-unit dependency. }
procedure SinCosApprox(a: Double; var s, c: Double);
var x, x2: Double;
begin
  x := a;
  while x >  3.14159265358979 do x := x - 6.28318530717959;
  while x < -3.14159265358979 do x := x + 6.28318530717959;
  x2 := x * x;
  s := x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0));
  c := 1.0 - x2 / 2.0 * (1.0 - x2 / 12.0 * (1.0 - x2 / 30.0));
end;

{ ---------------- main ---------------- }

var
  argi, frameLimit, workerOverride, fpsCap, budgetUs: Integer;
  arg: AnsiString;
  doRotate, checkOnly, bounded: Boolean;
  bad, checked: Integer;
  cols, rows, w, h, prevW, prevH: Integer;
  frame: AnsiString;
  ti, frameNo, maxIt, shift: Integer;
  span, spanIm, aspect, zoomStep, angle, cosA, sinA: Double;
  useFixed: Boolean;
  t0, t1, tFrame: Int64;
  key: Char;
  quit: Boolean;
  kernelName: AnsiString;

begin
  frameLimit := 0; workerOverride := 0; fpsCap := DEFAULT_FPS;
  doRotate := True; checkOnly := False;
  argi := 1;
  while argi <= ParamCount do
  begin
    arg := ParamStr(argi);
    if arg = '--frames' then begin argi := argi + 1; frameLimit := StrToInt(ParamStr(argi)); end
    else if arg = '--fps' then begin argi := argi + 1; fpsCap := StrToInt(ParamStr(argi)); end
    else if arg = '--workers' then begin argi := argi + 1; workerOverride := StrToInt(ParamStr(argi)); end
    else if arg = '--no-rotate' then doRotate := False
    else if arg = '--check' then checkOnly := True
    else
    begin
      writeln('usage: mandelzoom [--frames N] [--fps N] [--workers N] [--no-rotate] [--check]');
      Halt(2);
    end;
    argi := argi + 1;
  end;

  BuildPalette;
  InitTargets;

  { The asm kernel is never trusted unverified — this runs on every start, not
    just under --check, and it is bounded and single-threaded. }
  bad := CheckAsmKernel(checked);
  if bad <> 0 then
  begin
    writeln('ASM KERNEL MISMATCH: ', bad, ' of ', checked,
            ' grid points disagree with the portable fixed-point kernel (BUG)');
    Halt(1);
  end;

  if checkOnly then
  begin
    if HaveAsmKernel then kernelName := 'inline-asm Q4.28 (x86-64)'
    else kernelName := 'portable Q4.28 (no asm kernel for this target)';
    writeln('kernel: ', kernelName);
    writeln('asm == portable on all ', checked, ' grid points  — OK');
    Halt(0);
  end;

  if workerOverride > 0 then PXXSetParForWorkers(workerOverride);

  bounded := frameLimit > 0;
  prevW := 0; prevH := 0;
  ti := 0; frameNo := 0; angle := 0.0; quit := False;
  span := 3.0;
  zoomStep := 0.97;

  AnsiWrite(AnsiAltScreen(True));
  AnsiWrite(AnsiHideCursor);
  AnsiSetRawMode(True);
  try
    while not quit do
    begin
      if not TerminalSize(cols, rows) then begin cols := 80; rows := 24; end;
      if cols > 200 then cols := 200;
      if rows > 60 then rows := 60;
      rows := rows - 1;                 { keep the last line for status }
      if rows < 4 then rows := 4;
      w := cols; h := rows * 2;         { half-blocks: two pixels per cell }
      if (w <> prevW) or (h <> prevH) then
      begin
        SetLength(fb, w * h);
        prevW := w; prevH := h;
        AnsiWrite(AnsiClear);
      end;

      { Iteration budget grows with depth — a deep zoom needs more iterations to
        keep any structure at all. }
      maxIt := MAXIT_MIN;
      if span < 0.01   then maxIt := 300;
      if span < 0.0005 then maxIt := 550;
      if span < 0.00002 then maxIt := MAXIT_MAX;

      useFixed := HaveAsmKernel and (span > FIXED_SPAN_FLOOR);
      if useFixed then kernelName := 'asm Q4.28' else kernelName := 'float';

      aspect := (h / 2.0) / w;          { half-blocks are ~square per pixel pair }
      spanIm := span * aspect * 2.0;

      if doRotate then SinCosApprox(angle, sinA, cosA)
      else begin sinA := 0.0; cosA := 1.0; end;

      { Publish this frame's parameters, then render. Written only here, read
        only by the workers — no concurrent access. }
      gW := w; gH := h; gMaxIt := maxIt; gUseFixed := useFixed;
      gCx := targets[ti].re; gCy := targets[ti].im;
      gSpanRe := span; gSpanIm := spanIm; gCosA := cosA; gSinA := sinA;

      t0 := NowUsec;
      RenderFrame;
      t1 := NowUsec;
      tFrame := t1 - t0;
      if tFrame <= 0 then tFrame := 1;

      shift := (frameNo * 3) mod PALSIZE;
      { Compose off-screen, then swap the whole frame in with ONE write. }
      frame := ComposeFrame(w, cols, rows, maxIt, shift);
      AnsiWrite(frame);
      AnsiWrite(AnsiMove(rows + 1, 1) + AnsiReset +
                targets[ti].name + '  span=' + FloatToStr(span) +
                '  it=' + IntStr(maxIt) +
                '  kernel=' + kernelName +
                '  workers=' + IntStr(PXXParForWorkers) +
                '  ' + IntStr(1000000 div tFrame) + ' fps  [q quits]   ');

      span := span * zoomStep;
      angle := angle + 0.01;
      frameNo := frameNo + 1;

      { Reached the target depth: pull back out and cut to the next point. }
      if span < targets[ti].depth then
      begin
        ti := (ti + 1) mod TARGETCOUNT;
        span := 3.0;
        AnsiWrite(AnsiClear);
      end;

      { Pace the animation. A shallow frame renders in well under a millisecond,
        so without a cap the zoom path blurs past; at depth the render itself
        exceeds the budget and this sleeps for nothing. }
      if fpsCap > 0 then
      begin
        budgetUs := 1000000 div fpsCap;
        if tFrame < budgetUs then Sleep((budgetUs - tFrame) div 1000);
      end;

      if bounded and (frameNo >= frameLimit) then quit := True;

      key := AnsiReadKey;
      if (key = 'q') or (key = 'Q') or (key = #27) then quit := True;
    end;
  finally
    AnsiSetRawMode(False);
    AnsiWrite(AnsiShowCursor);
    AnsiWrite(AnsiAltScreen(False));
  end;
  writeln('rendered ', frameNo, ' frames');
end.
