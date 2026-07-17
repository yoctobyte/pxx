{ SPDX-License-Identifier: 0BSD }
program MandelbrotParallel;
{ Mandelbrot — a `parallel for` demo. The image is rendered row-by-row across
  every CPU core with the language's `parallel for`, then the SAME work is run
  single-threaded, and the two escape-count checksums are asserted equal. That
  equality is the whole point: a data-parallel render must be bit-identical to
  the serial one, and the wall-clock ratio shows the multicore speedup.

  Modes:
    mandelbrot_parallel                 default 320x240, MAXIT 1000: serial vs
                                        parallel timing + checksum-equality oracle
    mandelbrot_parallel W H IT          custom size / iteration cap
    mandelbrot_parallel ... --ppm FILE  also write a colour PPM (P3) of the result

  SAFE-PARALLELISM PATTERN (see bug-a... rejected / the parallel-for notes):
  `parallel for` captures enclosing locals BY-REF (shared), so a value written by
  every worker races. Here each worker writes DISJOINT rows of the shared global
  `Esc` buffer (row r -> Esc[r*IW .. r*IW+IW-1]) and every scratch value lives in
  RenderRow's own locals (private per call, on the worker's stack). No shared
  mutable scalar, no per-worker heap alloc -> no race. Build --threadsafe.

  Track B / E (example app). Deterministic checksum oracle (serial == parallel);
  visual PPM for humans. Reuses the portable Double escape-time kernel. }

uses sysutils, baseunix, palparallel;

const
  RE_MIN: Double = -2.50;
  RE_MAX: Double =  1.00;
  IM_MIN: Double = -1.25;
  IM_MAX: Double =  1.25;
  MAX_PIXELS = 4000000;         { hard cap on IW*IH (buffer bound) }
  MAX_ROWS   = 8192;            { hard cap on IH (RowOrder bound) }

type
  TEscBuf   = array[0..MAX_PIXELS-1] of Integer;
  TRowOrder = array[0..MAX_ROWS-1] of Integer;

var
  Esc: TEscBuf;                 { shared result buffer; workers write disjoint rows }
  IW, IH, MAXIT: Integer;       { image size + iteration cap (globals: read-only in body) }
  RowOrder: TRowOrder;          { interleaved row visit order for load balance }

{ ---- portable Double escape-time kernel (matches mandelbrot.pas) ---- }
function EscapeCountLimit(cre, cim: Double; max_it: Integer): Integer;
var zre, zim, zr2, zi2, tmp: Double; i: Integer;
begin
  zre := 0.0; zim := 0.0; zr2 := 0.0; zi2 := 0.0; i := 0;
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

{ Render ONE row into its disjoint slice of Esc. Every variable here is a private
  local on the calling worker's stack — the only shared touch is Esc[base+col],
  and rows never overlap, so workers never collide. }
procedure RenderRow(row: Integer);
var col, base: Integer; cre, cim, dre, dim: Double;
begin
  dre := (RE_MAX - RE_MIN) / (IW - 1);
  dim := (IM_MAX - IM_MIN) / (IH - 1);
  cim := IM_MIN + row * dim;
  base := row * IW;
  for col := 0 to IW - 1 do
  begin
    cre := RE_MIN + col * dre;
    Esc[base + col] := EscapeCountLimit(cre, cim, MAXIT);
  end;
end;

{ Build the interleaved visit order. PXXParallelFor hands worker i a CONTIGUOUS
  block of the loop range, so a plain `for row := 0 to IH-1` gives worker i rows
  [i*IH/nw .. ]. For Mandelbrot that is pathological: the in-set rows (expensive,
  hit MAXIT) cluster in the middle, so one worker does most of the work and the
  speedup collapses. Interleaving fixes it: bucket b = rows b, b+nw, b+2nw, ...;
  concatenating the buckets means each worker's contiguous chunk is every nw-th
  row, spread across the whole image, so every worker sees a fair mix of cheap
  and costly rows. Output is order-independent — each row writes its own slot. }
procedure BuildRowOrder(nw: Integer);
var b, r, k: Integer;
begin
  if nw < 1 then nw := 1;
  k := 0;
  for b := 0 to nw - 1 do
  begin
    r := b;
    while r < IH do begin RowOrder[k] := r; Inc(k); r := r + nw; end;
  end;
end;

{ The parallel render: one `parallel for` over the interleaved row order. }
procedure RenderParallel;
var k: Integer;
begin
  BuildRowOrder(PXXParForWorkers);
  parallel for k := 0 to IH - 1 do
    RenderRow(RowOrder[k]);
end;

{ The serial render: identical work, pinned to a single worker. }
procedure RenderSerial;
var row: Integer;
begin
  PXXSetParForWorkers(1);
  parallel for row := 0 to IH - 1 do
    RenderRow(row);
  PXXSetParForWorkers(0);        { restore auto worker count }
end;

{ Positional checksum over the whole buffer (weight by index so any shift shows). }
function Checksum: Int64;
var i: Integer; s: Int64;
begin
  s := 0;
  for i := 0 to IW * IH - 1 do s := s + Int64(Esc[i]) * (i + 1) + Esc[i];
  Checksum := s;
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

procedure ClearBuf;
var i: Integer;
begin
  for i := 0 to IW * IH - 1 do Esc[i] := 0;
end;

procedure PaletteAt(n: Integer; var r, g, b: Integer);
begin
  if n >= MAXIT then begin r := 0; g := 0; b := 0; end
  else begin r := (n * 7) mod 256; g := (n * 5) mod 256; b := (n * 11) mod 256; end;
end;

procedure WritePPM(const path: AnsiString);
var f: Text; row, col, n, r, g, b: Integer; line: AnsiString;
begin
  Assign(f, path); Rewrite(f);
  writeln(f, 'P3');
  writeln(f, IntToStr(IW) + ' ' + IntToStr(IH));
  writeln(f, '255');
  for row := 0 to IH - 1 do
  begin
    line := '';
    for col := 0 to IW - 1 do
    begin
      n := Esc[row * IW + col];
      PaletteAt(n, r, g, b);
      line := line + IntToStr(r) + ' ' + IntToStr(g) + ' ' + IntToStr(b) + ' ';
    end;
    writeln(f, line);
  end;
  Close(f);
  writeln('wrote ', path, ' (', IW, 'x', IH, ')');
end;

function IsNum(const s: AnsiString): Boolean;
begin
  IsNum := (Length(s) > 0) and (s[1] >= '0') and (s[1] <= '9');
end;

var
  t0, t1, usSerial, usPar: Int64;
  csSerial, csPar: Int64;
  i, argIW, argIH, argIT: Integer;
  a, ppmPath: AnsiString;
  doPPM: Boolean;
begin
  IW := 320; IH := 240; MAXIT := 1000;
  doPPM := False; ppmPath := 'mandelbrot.ppm';

  { positional W H IT, then optional --ppm FILE }
  i := 1;
  if (ParamCount >= 1) and IsNum(ParamStr(1)) then
  begin
    argIW := StrToIntDef(ParamStr(1), IW); if argIW > 0 then IW := argIW;
    if (ParamCount >= 2) and IsNum(ParamStr(2)) then
    begin
      argIH := StrToIntDef(ParamStr(2), IH); if argIH > 0 then IH := argIH;
    end;
    if (ParamCount >= 3) and IsNum(ParamStr(3)) then
    begin
      argIT := StrToIntDef(ParamStr(3), MAXIT); if argIT > 0 then MAXIT := argIT;
    end;
  end;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if a = '--ppm' then
    begin
      doPPM := True;
      if i + 1 <= ParamCount then begin ppmPath := ParamStr(i + 1); i := i + 1; end;
    end;
    i := i + 1;
  end;

  if IW * IH > MAX_PIXELS then
  begin
    writeln('error: IW*IH (', IW * IH, ') exceeds MAX_PIXELS (', MAX_PIXELS, ')');
    Halt(1);
  end;
  if IH > MAX_ROWS then
  begin
    writeln('error: IH (', IH, ') exceeds MAX_ROWS (', MAX_ROWS, ')');
    Halt(1);
  end;

  writeln('Mandelbrot parallel demo — ', IW, 'x', IH, ', MAXIT=', MAXIT);
  writeln('cores (PXXParForWorkers) = ', PXXParForWorkers);

  { serial baseline }
  ClearBuf;
  t0 := NowUsec; RenderSerial; t1 := NowUsec;
  usSerial := t1 - t0; if usSerial <= 0 then usSerial := 1;
  csSerial := Checksum;

  { parallel }
  ClearBuf;
  t0 := NowUsec; RenderParallel; t1 := NowUsec;
  usPar := t1 - t0; if usPar <= 0 then usPar := 1;
  csPar := Checksum;

  writeln('serial   : ', usSerial, ' us   checksum=', csSerial);
  writeln('parallel : ', usPar, ' us   checksum=', csPar);
  writeln('speedup  : ', (usSerial * 100) div usPar, ' /100x  (', PXXParForWorkers, ' workers)');

  if doPPM then WritePPM(ppmPath);

  if csSerial = csPar then writeln('CHECKSUM MATCH — parallel render is bit-identical to serial')
  else begin writeln('CHECKSUM MISMATCH — BUG (serial ', csSerial, ' <> parallel ', csPar, ')'); Halt(1); end;
end.
