program Mandelbrot;
{ Mandelbrot — a float-compute demo built on the Double arithmetic the math
  library exercises, with a portable fixed-point (Int64 Q4.28) kernel, a colour
  PPM image renderer, and a benchmark mode.

  Modes (no args = the original deterministic ASCII smoke, unchanged so it stays
  the lib-test/demos gate):

    mandelbrot                       ASCII grid + escape-count CHECKSUM oracle
    mandelbrot --ppm FILE [W H]      render a colour PPM (P3) image
    mandelbrot --bench [W H]         render to memory, print pixels/s + iters/s
    mandelbrot --kernel float|fixed  select the escape-time kernel (default float)

  Determinism: strict IEEE-754 Double is bit-identical across modern targets
  (x86-64 SSE2, AArch64/ARM VFP, and software float emulation all compute the
  same 64-bit result), so the escape counts -- and thus the whole grid and its
  CHECKSUM -- SHOULD be identical on every target. The oracle asserts the integer
  checksum against the reference value (EXPECTED). A mismatch is a BUG signal
  (e.g. x87 80-bit intermediates leaking, or non-strict FMA contraction), not
  accepted tolerance -- this is exactly what feature-real-cross-target-consistency
  is meant to catch. FPC (-Mobjfpc) computes the same checksum, confirming it.

  The fixed-point kernel uses a Q4.28 representation in Int64: the canonical
  window stays well within 4 integer bits, products fit Int64 before the >>28
  renormalise, and the path touches no math.pas / float runtime at all -- it is
  the integer-only kernel the ticket asks for and a second deterministic oracle.

  Track B; integer-deterministic gate (checksum), visual grid for humans. }

uses sysutils, baseunix;

const
  W = 70;
  H = 32;
  MAXIT = 200;
  RE_MIN: Double = -2.50;
  RE_MAX: Double =  1.00;
  IM_MIN: Double = -1.25;
  IM_MAX: Double =  1.25;
  EXPECTED = 3745966;    { escape-count checksum on x86-64 (reference target) }

  FRAC  = 28;            { fixed-point fractional bits (Q4.28) }
  ONE   = 268435456;     { 1.0 in Q4.28 = 1 shl 28 }
  FOUR  = 1073741824;    { 4.0 in Q4.28 = 4 shl 28 (escape radius^2) }

{ ---- portable Double escape-time kernel (the reference; do not touch: the
  smoke CHECKSUM is pinned to its output) ---- }
function EscapeCount(cre, cim: Double): Integer;
var zre, zim, zr2, zi2, tmp: Double; i: Integer;
begin
  zre := 0.0; zim := 0.0;
  zr2 := 0.0; zi2 := 0.0;
  i := 0;
  while (i < MAXIT) and (zr2 + zi2 <= 4.0) do
  begin
    tmp := zr2 - zi2 + cre;
    zim := 2.0 * zre * zim + cim;
    zre := tmp;
    zr2 := zre * zre;
    zi2 := zim * zim;
    i := i + 1;
  end;
  EscapeCount := i;
end;

{ ---- integer-only escape-time kernel: cre/cim are Q4.28 fixed-point ---- }
function EscapeCountFixed(cre, cim: Int64): Integer;
var zre, zim, zr2, zi2, tmp: Int64; i: Integer;
begin
  zre := 0; zim := 0;
  zr2 := 0; zi2 := 0;
  i := 0;
  while (i < MAXIT) and (zr2 + zi2 <= FOUR) do
  begin
    tmp := zr2 - zi2 + cre;
    zim := ((2 * zre * zim) div ONE) + cim;   { div ONE == >>FRAC, sign-correct }
    zre := tmp;
    zr2 := (zre * zre) div ONE;
    zi2 := (zim * zim) div ONE;
    i := i + 1;
  end;
  EscapeCountFixed := i;
end;

{ Double -> Q4.28; Trunc toward zero is fine for the demo window. }
function ToFixed(d: Double): Int64;
begin
  ToFixed := Trunc(d * 268435456.0);
end;

{ Deterministic integer colour palette (no math.pas): black inside the set,
  a cheap multi-frequency gradient outside. r,g,b in 0..255. }
procedure Palette(n: Integer; var r, g, b: Integer);
begin
  if n >= MAXIT then
  begin
    r := 0; g := 0; b := 0;
  end
  else
  begin
    r := (n * 7)  mod 256;
    g := (n * 5)  mod 256;
    b := (n * 11) mod 256;
  end;
end;

{ Microsecond wall clock for the benchmark. }
function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then
    NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else
    NowUsec := 0;
end;

function KName(useFixed: Boolean): AnsiString;
begin
  if useFixed then KName := 'fixed' else KName := 'float';
end;

function EscapeAt(useFixed: Boolean; cre, cim: Double): Integer;
begin
  if useFixed then
    EscapeAt := EscapeCountFixed(ToFixed(cre), ToFixed(cim))
  else
    EscapeAt := EscapeCount(cre, cim);
end;

const
  RAMP = ' .:-=+*#%@';      { 10 shades, low escape -> high }

{ ---- mode 1: ASCII grid + escape-count checksum (the gate; unchanged) ---- }
procedure RunSmoke;
var
  row, col, n, ri: Integer;
  cre, cim, dre, dim: Double;
  line: AnsiString;
  checksum: Int64;
begin
  dre := (RE_MAX - RE_MIN) / (W - 1);
  dim := (IM_MAX - IM_MIN) / (H - 1);
  checksum := 0;

  for row := 0 to H - 1 do
  begin
    cim := IM_MIN + row * dim;
    line := '';
    for col := 0 to W - 1 do
    begin
      cre := RE_MIN + col * dre;
      n := EscapeCount(cre, cim);
      { positional checksum: weight by column so a horizontal shift is caught }
      checksum := checksum + n * (col + 1) + n;
      if n >= MAXIT then line := line + '@'          { inside the set }
      else
      begin
        ri := (n * 10) div MAXIT;                    { 0..9 ramp }
        if ri > 9 then ri := 9;
        line := line + RAMP[ri + 1];
      end;
    end;
    writeln(line);
  end;

  writeln;
  writeln('checksum=', checksum);
  if checksum = EXPECTED then writeln('ALL OK')
  else writeln('FAILURES (want ', EXPECTED, ')');
end;

{ ---- mode 2: colour PPM (P3) render ---- }
procedure RunPPM(const path: AnsiString; iw, ih: Integer; useFixed: Boolean);
var
  f: Text;
  row, col, n, r, g, b: Integer;
  cre, cim, dre, dim: Double;
  rgbsum: Int64;
  line: AnsiString;
begin
  dre := (RE_MAX - RE_MIN) / (iw - 1);
  dim := (IM_MAX - IM_MIN) / (ih - 1);
  rgbsum := 0;

  Assign(f, path);
  Rewrite(f);
  writeln(f, 'P3');
  writeln(f, IntToStr(iw) + ' ' + IntToStr(ih));
  writeln(f, '255');

  for row := 0 to ih - 1 do
  begin
    cim := IM_MIN + row * dim;
    line := '';
    for col := 0 to iw - 1 do
    begin
      cre := RE_MIN + col * dre;
      n := EscapeAt(useFixed, cre, cim);
      Palette(n, r, g, b);
      rgbsum := rgbsum + (r + 2 * g + 3 * b) * (col + 1);
      line := line + IntToStr(r) + ' ' + IntToStr(g) + ' ' + IntToStr(b) + ' ';
    end;
    writeln(f, line);
  end;
  Close(f);

  writeln('wrote ', path, ' (', iw, 'x', ih, ', kernel=', KName(useFixed), ')');
  writeln('rgbsum=', rgbsum);
end;

{ ---- mode 3: benchmark (render to nothing, just count work + time it) ---- }
procedure RunBench(iw, ih: Integer; useFixed: Boolean);
var
  row, col, n: Integer;
  cre, cim, dre, dim: Double;
  t0, t1, us: Int64;
  pixels, iters: Int64;
begin
  dre := (RE_MAX - RE_MIN) / (iw - 1);
  dim := (IM_MAX - IM_MIN) / (ih - 1);
  pixels := 0; iters := 0;

  t0 := NowUsec;
  for row := 0 to ih - 1 do
  begin
    cim := IM_MIN + row * dim;
    for col := 0 to iw - 1 do
    begin
      cre := RE_MIN + col * dre;
      n := EscapeAt(useFixed, cre, cim);
      pixels := pixels + 1;
      iters := iters + n;
    end;
  end;
  t1 := NowUsec;
  us := t1 - t0;
  if us <= 0 then us := 1;

  writeln('kernel   = ', KName(useFixed));
  writeln('size     = ', iw, 'x', ih, ' (', pixels, ' px)');
  writeln('iters    = ', iters);
  writeln('elapsed  = ', us, ' us');
  writeln('px/s     = ', (pixels * 1000000) div us);
  writeln('iters/s  = ', (iters  * 1000000) div us);
end;

var
  i, iw, ih: Integer;
  mode, a, ppmPath, kernel: AnsiString;
  useFixed: Boolean;
begin
  mode := 'smoke';
  ppmPath := 'mandelbrot.ppm';
  kernel := 'float';
  iw := 280; ih := 200;   { window aspect 3.5/2.5 = 1.4 ~ 280/200 }

  i := 1;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if a = '--ppm' then
    begin
      mode := 'ppm';
      if i + 1 <= ParamCount then begin ppmPath := ParamStr(i + 1); i := i + 1; end;
      if i + 2 <= ParamCount then
      begin
        iw := StrToIntDef(ParamStr(i + 1), iw);
        ih := StrToIntDef(ParamStr(i + 2), ih);
        i := i + 2;
      end;
    end
    else if a = '--bench' then
    begin
      mode := 'bench';
      if i + 2 <= ParamCount then
      begin
        iw := StrToIntDef(ParamStr(i + 1), iw);
        ih := StrToIntDef(ParamStr(i + 2), ih);
        i := i + 2;
      end;
    end
    else if a = '--kernel' then
    begin
      if i + 1 <= ParamCount then begin kernel := ParamStr(i + 1); i := i + 1; end;
    end;
    i := i + 1;
  end;

  useFixed := kernel = 'fixed';

  if mode = 'ppm' then RunPPM(ppmPath, iw, ih, useFixed)
  else if mode = 'bench' then RunBench(iw, ih, useFixed)
  else RunSmoke;
end.
