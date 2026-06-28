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

uses sysutils, baseunix, ansiterm;

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
function EscapeCountLimit(cre, cim: Double; max_it: Integer): Integer;
var zre, zim, zr2, zi2, tmp: Double; i: Integer;
begin
  zre := 0.0; zim := 0.0;
  zr2 := 0.0; zi2 := 0.0;
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
  EscapeCountLimit := i;
end;

function EscapeCount(cre, cim: Double): Integer;
begin
  EscapeCount := EscapeCountLimit(cre, cim, MAXIT);
end;

{ ---- integer-only escape-time kernel: cre/cim are Q4.28 fixed-point ---- }
function EscapeCountFixedLimit(cre, cim: Int64; max_it: Integer): Integer;
var zre, zim, zr2, zi2, tmp: Int64; i: Integer;
begin
  zre := 0; zim := 0;
  zr2 := 0; zi2 := 0;
  i := 0;
  while (i < max_it) and (zr2 + zi2 <= FOUR) do
  begin
    tmp := zr2 - zi2 + cre;
    zim := ((2 * zre * zim) div ONE) + cim;   { div ONE == >>FRAC, sign-correct }
    zre := tmp;
    zr2 := (zre * zre) div ONE;
    zi2 := (zim * zim) div ONE;
    i := i + 1;
  end;
  EscapeCountFixedLimit := i;
end;

function EscapeCountFixed(cre, cim: Int64): Integer;
begin
  EscapeCountFixed := EscapeCountFixedLimit(cre, cim, MAXIT);
end;

{ Double -> Q4.28; Trunc toward zero is fine for the demo window. }
function ToFixed(d: Double): Int64;
begin
  ToFixed := Trunc(d * 268435456.0);
end;

{ Deterministic integer colour palette (no math.pas): black inside the set,
  a cheap multi-frequency gradient outside. r,g,b in 0..255. }
procedure PaletteLimit(n, max_it: Integer; var r, g, b: Integer);
begin
  if n >= max_it then
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

procedure Palette(n: Integer; var r, g, b: Integer);
begin
  PaletteLimit(n, MAXIT, r, g, b);
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

function ReadKeyAction: AnsiString;
var c, c2, c3: Char;
begin
  c := AnsiReadKeyWait;
  if c = #27 then
  begin
    c2 := AnsiReadKey;
    if c2 = '[' then
    begin
      c3 := AnsiReadKey;
      if c3 = 'A' then ReadKeyAction := 'up'
      else if c3 = 'B' then ReadKeyAction := 'down'
      else if c3 = 'C' then ReadKeyAction := 'right'
      else if c3 = 'D' then ReadKeyAction := 'left'
      else ReadKeyAction := 'esc';
    end
    else
    begin
      ReadKeyAction := 'esc';
    end;
  end
  else
  begin
    ReadKeyAction := c;
  end;
end;

procedure RenderTUIFrame(cre_min, cre_max, cim_min, cim_max: Double; max_it: Integer; use_fixed: Boolean);
var
  cols, rows, pw, ph, px, py, n: Integer;
  cre, cim, dre, dim: Double;
  r, g, b: Integer;
  line: AnsiString;
  lastR, lastG, lastB: Integer;
begin
  if not TerminalSize(cols, rows) then
  begin
    cols := 80;
    rows := 24;
  end;

  ph := rows - 1;
  pw := cols div 2;
  if pw < 1 then pw := 1;
  if ph < 1 then ph := 1;

  dre := (cre_max - cre_min) / (pw - 1);
  dim := (cim_max - cim_min) / (ph - 1);

  AnsiWrite(AnsiMove(1, 1));
  for py := 0 to ph - 1 do
  begin
    line := '';
    lastR := -1; lastG := -1; lastB := -1;
    cim := cim_min + py * dim;
    for px := 0 to pw - 1 do
    begin
      cre := cre_min + px * dre;
      if use_fixed then
        n := EscapeCountFixedLimit(ToFixed(cre), ToFixed(cim), max_it)
      else
        n := EscapeCountLimit(cre, cim, max_it);

      PaletteLimit(n, max_it, r, g, b);

      if (r <> lastR) or (g <> lastG) or (b <> lastB) then
      begin
        line := line + AnsiBgRGB(r, g, b);
        lastR := r; lastG := g; lastB := b;
      end;
      line := line + '  ';
    end;
    AnsiWrite(line);
    if py < ph - 1 then
      AnsiWrite(#13#10);
  end;

  AnsiWrite(AnsiReset);
  AnsiWrite(AnsiMove(rows, 1));
  line := 'Center: (' + FloatToStrF((cre_min + cre_max) * 0.5, 4) + ', ' + FloatToStrF((cim_min + cim_max) * 0.5, 4) + ') | Zoom: ' + FloatToStrF(3.5 / (cre_max - cre_min), 2) + ' | MaxIt: ' + IntToStr(max_it) + ' | Kernel: ';
  if use_fixed then line := line + 'fixed' else line := line + 'float';
  line := line + ' | [ARROWS]/[WASD] Pan | [+/-] Zoom | [[/]] MaxIt | [K] Kernel | [R] Reset | [Q] Quit';
  while Length(line) < cols do
    line := line + ' ';
  AnsiWrite(AnsiBold + line + AnsiReset);
end;

procedure RunTUI;
var
  cre_min, cre_max, cim_min, cim_max: Double;
  center_re, center_im, span_re, span_im: Double;
  max_it: Integer;
  use_fixed: Boolean;
  act: AnsiString;
  cols, rows: Integer;
  need_redraw: Boolean;
begin
  AnsiWrite(AnsiAltScreen(True));
  AnsiWrite(AnsiHideCursor);
  AnsiSetRawMode(True);

  try
    center_re := -0.75;
    center_im := 0.0;
    span_re := 3.0;
    max_it := 80;
    use_fixed := False;

    need_redraw := True;

    while True do
    begin
      if need_redraw then
      begin
        if not TerminalSize(cols, rows) then
        begin
          cols := 80;
          rows := 24;
        end;
        if cols < 2 then cols := 2;
        if rows < 2 then rows := 2;
        span_im := span_re * ((rows - 1) / (cols div 2));

        cre_min := center_re - span_re / 2.0;
        cre_max := center_re + span_re / 2.0;
        cim_min := center_im - span_im / 2.0;
        cim_max := center_im + span_im / 2.0;

        RenderTUIFrame(cre_min, cre_max, cim_min, cim_max, max_it, use_fixed);
        need_redraw := False;
      end;

      act := ReadKeyAction;
      if (act = 'q') or (act = 'Q') or (act = 'esc') then Break
      else if (act = 'up') or (act = 'w') or (act = 'W') then
      begin
        center_im := center_im - span_im * 0.1;
        need_redraw := True;
      end
      else if (act = 'down') or (act = 's') or (act = 'S') then
      begin
        center_im := center_im + span_im * 0.1;
        need_redraw := True;
      end
      else if (act = 'left') or (act = 'a') or (act = 'A') then
      begin
        center_re := center_re - span_re * 0.1;
        need_redraw := True;
      end
      else if (act = 'right') or (act = 'd') or (act = 'D') then
      begin
        center_re := center_re + span_re * 0.1;
        need_redraw := True;
      end
      else if (act = '+') or (act = '=') or (act = 'i') or (act = 'I') then
      begin
        span_re := span_re * 0.8;
        need_redraw := True;
      end
      else if (act = '-') or (act = 'o') or (act = 'O') then
      begin
        span_re := span_re * 1.25;
        need_redraw := True;
      end
      else if (act = ']') or (act = 'u') or (act = 'U') then
      begin
        max_it := max_it + 10;
        if max_it > 1000 then max_it := 1000;
        need_redraw := True;
      end
      else if (act = '[') or (act = 'd') or (act = 'D') then
      begin
        max_it := max_it - 10;
        if max_it < 10 then max_it := 10;
        need_redraw := True;
      end
      else if (act = 'k') or (act = 'K') then
      begin
        use_fixed := not use_fixed;
        need_redraw := True;
      end
      else if (act = 'r') or (act = 'R') then
      begin
        center_re := -0.75;
        center_im := 0.0;
        span_re := 3.0;
        max_it := 80;
        need_redraw := True;
      end;
    end;
  finally
    AnsiSetRawMode(False);
    AnsiWrite(AnsiShowCursor);
    AnsiWrite(AnsiAltScreen(False));
  end;
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
    else if a = '--tui' then
    begin
      mode := 'tui';
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
  else if mode = 'tui' then RunTUI
  else RunSmoke;
end.
