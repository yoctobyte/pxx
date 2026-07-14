program MandelbrotBench;
{ Float-compute benchmark: the mandelbrot escape-time kernel, and NOTHING else.

  This is the PORTABLE twin of examples/mandelbrot/mandelbrot.pas. Same window,
  same Double kernel, same positional checksum -- but it uses no unit at all, so
  FPC compiles it too and the bench suite can time both compilers on the same
  work (feature-t-bench-portable-variants).

  The example depends on `ansiterm` (a pxx-only RTL unit) for the terminal grid
  and `baseunix` for its internal microsecond clock. Neither has anything to do
  with the arithmetic being measured: the drawing is not timed, and testmgr times
  the PROCESS, so an in-program clock is redundant. Dropping both units costs the
  benchmark nothing and buys an external speed oracle -- which is the only way to
  tell "pxx is slow here" from "this workload is just expensive".

  A benchmark should not depend on libraries anyway: a library change would move
  the number and nobody would know whether the compiler or the library did it.

  The example stays as it is -- it is a Track B/E demo and exists to *use* our
  libraries. This is a bench fixture, not a replacement.

  Determinism: strict IEEE-754 Double is bit-identical across targets, so the
  escape counts, and therefore CHECKSUM, are identical everywhere -- including
  under FPC. That is what makes it a legitimate cross-compiler comparison: if the
  two compilers agree on the checksum, they did the same work, and the timings are
  comparable. A mismatch is a BUG signal (x87 80-bit intermediates leaking, or
  non-strict FMA contraction), never an accepted tolerance.

  Usage:  mandelbrot [W H]     (default 1600x1200, matching the example's --bench) }

const
  MAXIT = 200;
  RE_MIN: Double = -2.50;
  RE_MAX: Double =  1.00;
  IM_MIN: Double = -1.25;
  IM_MAX: Double =  1.25;
  { The 70x32 grid's checksum, pinned in the example as EXPECTED. Reproduced here
    so this file is self-validating against the same reference value. }
  SMOKE_W = 70;
  SMOKE_H = 32;
  SMOKE_EXPECTED = 3745966;

{ The reference Double kernel, character for character as the example's. Do not
  "improve" it: the checksum is pinned to its exact sequence of operations. }
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

{ The positional checksum: weighted by column, so a horizontal shift is caught
  rather than cancelling out. }
function GridChecksum(iw, ih: Integer): Int64;
var
  row, col, n: Integer;
  cre, cim, dre, dim: Double;
  cs: Int64;
begin
  dre := (RE_MAX - RE_MIN) / (iw - 1);
  dim := (IM_MAX - IM_MIN) / (ih - 1);
  cs := 0;
  for row := 0 to ih - 1 do
  begin
    cim := IM_MIN + row * dim;
    for col := 0 to iw - 1 do
    begin
      cre := RE_MIN + col * dre;
      n := EscapeCountLimit(cre, cim, MAXIT);
      cs := cs + n * (col + 1) + n;
    end;
  end;
  GridChecksum := cs;
end;

var
  iw, ih, code: Integer;
  smoke: Int64;
begin
  iw := 1600;
  ih := 1200;
  if ParamCount >= 2 then
  begin
    Val(ParamStr(1), iw, code);  if (code <> 0) or (iw < 2) then iw := 1600;
    Val(ParamStr(2), ih, code);  if (code <> 0) or (ih < 2) then ih := 1200;
  end;

  { Self-check on the pinned 70x32 grid FIRST: if the arithmetic is wrong, the
    timing below is meaningless and must not be reported as a benchmark result.
    Cheap (2240 pixels) next to the timed grid. }
  smoke := GridChecksum(SMOKE_W, SMOKE_H);
  if smoke <> SMOKE_EXPECTED then
  begin
    writeln('CHECKSUM MISMATCH: got ', smoke, ' expected ', SMOKE_EXPECTED);
    Halt(1);
  end;

  { The timed work. Printing the checksum keeps the whole grid live -- otherwise a
    sufficiently clever optimiser is entitled to delete the loop entirely, and the
    benchmark would measure nothing while looking fast. }
  writeln('checksum ', GridChecksum(iw, ih));
end.
