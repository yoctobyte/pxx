program Mandelbrot;
{ ASCII Mandelbrot — a float-compute demo built on the Double arithmetic the
  math library exercises. Renders an escape-time grid over a fixed window.

  Determinism: strict IEEE-754 Double is bit-identical across modern targets
  (x86-64 SSE2, AArch64/ARM VFP, and software float emulation all compute the
  same 64-bit result), so the escape counts -- and thus the whole grid and its
  CHECKSUM -- SHOULD be identical on every target. The oracle asserts the integer
  checksum against the reference value (EXPECTED). A mismatch is a BUG signal
  (e.g. x87 80-bit intermediates leaking, or non-strict FMA contraction), not
  accepted tolerance -- this is exactly what feature-real-cross-target-consistency
  is meant to catch. FPC (-Mobjfpc) computes the same checksum, confirming it.

  Track B; integer-deterministic gate (checksum), visual grid for humans. }

uses sysutils;

const
  W = 70;
  H = 32;
  MAXIT = 200;
  RE_MIN: Double = -2.50;
  RE_MAX: Double =  1.00;
  IM_MIN: Double = -1.25;
  IM_MAX: Double =  1.25;
  EXPECTED = 3745966;    { escape-count checksum on x86-64 (reference target) }

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

const
  RAMP = ' .:-=+*#%@';      { 10 shades, low escape -> high }

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
end.
