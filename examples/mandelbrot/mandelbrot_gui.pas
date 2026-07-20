{ SPDX-License-Identifier: 0BSD }
program MandelbrotGUI;
{ Interactive GUI Mandelbrot — pan/zoom on a tiled, MULTITHREADED renderer.

  The headline is the threading: the viewport is split into tile-rows and farmed
  out with `parallel(pdOnDemand)`, so a deep zoom uses every core. pdOnDemand
  rather than a contiguous split because per-row cost is wildly uneven — rows
  that fall inside the set burn the whole iteration budget while their
  neighbours escape in a handful of steps, and work stealing is what keeps the
  last worker from holding up the frame.

  Coarse-to-fine redraw: any view change renders immediately at 1/8 resolution
  (block-replicated, so it appears instantly), then refines 8 -> 4 -> 2 -> 1 on
  timer ticks. The window stays responsive during a deep zoom because each pass
  is a separate, short render and the event loop runs between them.

  THREADING DISCIPLINE. Workers only ever write escape counts into `fb`,
  partitioned by row, so no two touch the same element. All GTK/bitmap calls
  happen on the main thread, after the parallel render has joined — the toolkit
  is never entered from a worker. The render parameters live in globals because
  a parallel-for does not capture globals (they are statically addressable) and
  the capture path has open bugs for exactly the shapes this needs; see
  bug-parallel-for-captured-boolean-loses-type and
  bug-parallel-for-captured-dynarray-var-arg-segfault. They are written by the
  main thread between renders and only read during one, so there is no race.

  Controls:
    left click      zoom in 2x on that point       drag        pan
    right click     zoom out 2x                    +  /  -     zoom
    r               reset view                     q / Escape  quit
    [  /  ]         iteration budget down / up

  Usage:
    mandelbrot_gui             the window
    mandelbrot_gui --smoke     bounded offscreen render, print stats, exit
                               (no window — for a headless check)
    mandelbrot_gui --gui-smoke map the real window, run the real event loop,
                               self-quit after a moment (run it under Xvfb)

  NOT an automated stress test: nothing here is wired into `make lib-test` or
  `make demos` as a runtime test, per the ticket's guardrail. `make demos`
  compiles it and stops. Manual validation, or `--smoke` for a bounded look.

  Sibling demos: mandelbrot.pas is the deterministic checksum oracle (untouched
  by this one), mandelzoom.pas is the TUI auto-zoom with the inline-asm kernel.

  Track B/E (example app). Build --threadsafe. }

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, graphics, math, sysutils, baseunix,
     palparallel, mandelkernel;

const
  INIT_W    = 900;
  INIT_H    = 640;
  MAXIT_DEF = 300;
  PALSIZE   = 256;
  SMOKE_W   = 320;
  SMOKE_H   = 240;

type
  TPixels = array of Integer;

{ ---------------- render state (read by workers, see the header note) -------- }

var
  fb: TPixels;
  gW, gH, gMaxIt, gStep: Integer;
  gCx, gCy, gSpanRe, gSpanIm: Double;

{ One tile-row of the frame. The pixels of a row are handed to mandelkernel as a
  RUN, not one at a time: that is what lets the SSE2/AVX rungs keep 2 or 4 pixels
  in flight per iteration.

  The samples land in the FRONT of the row's own slice of fb and are then
  expanded in place, right to left (sample sx moves out to sx*gStep, which is
  never left of where it started, so nothing is overwritten before it is read).
  No temporary buffer: a per-row allocation here would put every worker through
  the one global heap spinlock, and on this shape that made the parallel render
  slower than the serial one — see feature-opt-heap-per-thread-cache.

  Writes only rows [y0 .. y0+gStep-1], so workers never overlap. }
procedure RenderTileRow(band: Integer);
var y0, y, x, sx, n, dx, dy, samples, base: Integer; cim: Double;
begin
  y0 := band * gStep;
  if y0 >= gH then Exit;
  base := y0 * gW;
  cim := gCy + ((y0 / (gH - 1)) - 0.5) * gSpanIm;

  samples := (gW + gStep - 1) div gStep;
  EscapeRow(fb, base, samples,
            gCx - 0.5 * gSpanRe,                 { first sample's real part }
            (gSpanRe / (gW - 1)) * gStep,        { step between samples }
            cim, gMaxIt);

  { expand the samples across the row, right to left }
  for sx := samples - 1 downto 0 do
  begin
    n := fb[base + sx];
    for dx := gStep - 1 downto 0 do
    begin
      x := sx * gStep + dx;
      if x < gW then fb[base + x] := n;
    end;
  end;

  { replicate the finished row down over the rest of its block }
  for dy := 1 to gStep - 1 do
  begin
    y := y0 + dy;
    if y >= gH then Break;
    for x := 0 to gW - 1 do fb[y * gW + x] := fb[base + x];
  end;
end;

{ The multithreaded render. pdOnDemand: uneven per-row cost is the whole reason
  the policy matters here. }
procedure RenderFrame;
var band, bands: Integer;
begin
  bands := (gH + gStep - 1) div gStep;
  parallel(pdOnDemand) for band := 0 to bands - 1 do RenderTileRow(band);
end;

{ ---------------- palette ---------------- }

var
  pal: array[0..PALSIZE - 1] of Integer;

function Lobe(t, phase: Integer): Integer;
var u, v: Integer;
begin
  u := (t + phase) mod PALSIZE;
  if u < PALSIZE div 2 then v := u * 2 else v := (PALSIZE - u) * 2 - 1;
  Lobe := v;
end;

procedure BuildPalette;
var i, r, g, b: Integer;
begin
  for i := 0 to PALSIZE - 1 do
  begin
    r := Lobe(i, 0);
    g := Lobe(i, PALSIZE div 3);
    b := Lobe(i, (2 * PALSIZE) div 3);
    { TColor here is $00BBGGRR (see TBitmap.SetPixel), not $00RRGGBB. }
    pal[i] := (b shl 16) or (g shl 8) or r;
  end;
end;

{ sqrt of the escape count, not the count itself: almost every pixel outside the
  set escapes in the first few iterations, so a linear index crams the entire
  outer region into one narrow band of the palette. sqrt spreads the low counts
  out and compresses the high ones, which is where the classic look comes from. }
function ColorOf(n, maxIt: Integer): Integer;
begin
  if n >= maxIt then ColorOf := 0
  else ColorOf := pal[Trunc(Sqrt(n * 1.0) * 40.0) mod PALSIZE];
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

{ ---------------- the window ---------------- }

type
  TMandelHandler = class
  private
    FBitmap: TBitmap;
    FPaintBox: TPaintBox;
    FStatus: TLabel;

    FCx, FCy, FSpan: Double;
    FMaxIt: Integer;

    FStep: Integer;          { current quality: 8 -> 4 -> 2 -> 1 }
    FRefining: Boolean;      { a refine timeout is armed }
    FLastUs: Int64;

    FDragging: Boolean;
    FDragX, FDragY: Integer;

    procedure Blit;
    procedure UpdateStatus;
  public
    constructor Create(APaintBox: TPaintBox; AStatus: TLabel);
    destructor Destroy;

    procedure RenderAt(step: Integer);
    procedure Invalidate;      { view changed: restart the coarse-to-fine chain }
    function Refine: Boolean;  { timer tick; False when fully refined }

    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure DoMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseMove(Sender: TControl; Button, X, Y: Integer);
    procedure DoKeyDown(Sender: TControl; KeyCode: Integer);
    procedure DoResize(Sender: TControl; Width, Height: Integer);
  end;

function RefineCb(data: Pointer): Integer; cdecl; forward;

{ --gui-smoke: self-quit once the real event loop has actually run. }
function GuiAutoQuit(data: Pointer): Integer; cdecl;
begin
  writeln('GUI SMOKE OK');
  gtk_main_quit;
  GuiAutoQuit := 0;
end;

constructor TMandelHandler.Create(APaintBox: TPaintBox; AStatus: TLabel);
begin
  FPaintBox := APaintBox;
  FStatus := AStatus;
  FCx := -0.75; FCy := 0.0; FSpan := 3.2;
  FMaxIt := MAXIT_DEF;
  FStep := 1;
  FRefining := False;
  FDragging := False;
  FLastUs := 1;

  FBitmap := TBitmap.Create;
  FBitmap.Width := INIT_W;
  FBitmap.Height := INIT_H;
  FBitmap.Clear($00000000);
  SetLength(fb, INIT_W * INIT_H);
end;

destructor TMandelHandler.Destroy;
begin
  FBitmap.Destroy;
end;

{ Main thread only — the parallel render has already joined. }
procedure TMandelHandler.Blit;
var x, y, w, h: Integer;
begin
  w := FBitmap.Width; h := FBitmap.Height;
  for y := 0 to h - 1 do
    for x := 0 to w - 1 do
      FBitmap.SetPixel(x, y, ColorOf(fb[y * w + x], FMaxIt));
end;

procedure TMandelHandler.UpdateStatus;
var fps: Int64;
begin
  if FLastUs <= 0 then FLastUs := 1;
  fps := 1000000 div FLastUs;
  FStatus.Caption :=
    'span ' + FloatToStr(FSpan) +
    '   it ' + IntToStr(FMaxIt) +
    '   1/' + IntToStr(FStep) + ' res' +
    '   ' + IntToStr(PXXParForWorkers) + ' workers' +
    '   ' + ISAName(ActiveISA) +
    '   ' + IntToStr(FLastUs div 1000) + ' ms (' + IntToStr(fps) + ' fps)' +
    '   [drag pan, click zoom, r reset, q quit]';
end;

procedure TMandelHandler.RenderAt(step: Integer);
var t0: Int64;
begin
  gW := FBitmap.Width;
  gH := FBitmap.Height;
  if (gW <= 1) or (gH <= 1) then Exit;
  if Length(fb) < gW * gH then SetLength(fb, gW * gH);

  gMaxIt := FMaxIt;
  gStep := step;
  gCx := FCx; gCy := FCy;
  gSpanRe := FSpan;
  gSpanIm := FSpan * (gH / gW);

  t0 := NowUsec;
  RenderFrame;
  FLastUs := NowUsec - t0;

  FStep := step;
  Blit;
  UpdateStatus;
  FPaintBox.Invalidate;
end;

procedure TMandelHandler.Invalidate;
begin
  { Coarse pass first so the new view appears at once, then let the timer walk
    it down to full resolution. }
  RenderAt(8);
  if not FRefining then
  begin
    FRefining := True;
    g_timeout_add(16, @RefineCb, Pointer(Self));
  end;
end;

function TMandelHandler.Refine: Boolean;
begin
  if FStep <= 1 then
  begin
    FRefining := False;
    Refine := False;
    Exit;
  end;
  RenderAt(FStep div 2);
  Refine := FStep > 1;
  if not Refine then FRefining := False;
end;

function RefineCb(data: Pointer): Integer; cdecl;
var h: TMandelHandler;
begin
  h := TMandelHandler(data);
  if h.Refine then RefineCb := 1 else RefineCb := 0;
end;

procedure TMandelHandler.OnPaint(Sender: TControl; Canvas: TCanvas);
begin
  Canvas.Draw(0, 0, FBitmap);
end;

procedure TMandelHandler.DoMouseDown(Sender: TControl; Button, X, Y: Integer);
begin
  FDragging := True;
  FDragX := X; FDragY := Y;
end;

{ A click that did not drag is a zoom; a drag that moved is a pan (already
  applied in DoMouseMove). }
procedure TMandelHandler.DoMouseUp(Sender: TControl; Button, X, Y: Integer);
var w, h: Integer; sx, sy: Double;
begin
  FDragging := False;
  if (Abs(X - FDragX) > 2) or (Abs(Y - FDragY) > 2) then Exit;

  w := FBitmap.Width; h := FBitmap.Height;
  if (w <= 1) or (h <= 1) then Exit;
  sx := (X / (w - 1)) - 0.5;
  sy := (Y / (h - 1)) - 0.5;

  if Button = 3 then
  begin
    FSpan := FSpan * 2.0;
  end
  else
  begin
    { Recentre on the clicked point, then halve the window. }
    FCx := FCx + sx * FSpan;
    FCy := FCy + sy * FSpan * (h / w);
    FSpan := FSpan * 0.5;
  end;
  Invalidate;
end;

procedure TMandelHandler.DoMouseMove(Sender: TControl; Button, X, Y: Integer);
var w, h, dx, dy: Integer;
begin
  if not FDragging then Exit;
  dx := X - FDragX; dy := Y - FDragY;
  if (dx = 0) and (dy = 0) then Exit;
  w := FBitmap.Width; h := FBitmap.Height;
  if (w <= 1) or (h <= 1) then Exit;
  FCx := FCx - (dx / (w - 1)) * FSpan;
  FCy := FCy - (dy / (h - 1)) * FSpan * (h / w);
  FDragX := X; FDragY := Y;
  Invalidate;
end;

procedure TMandelHandler.DoKeyDown(Sender: TControl; KeyCode: Integer);
begin
  { Numeric literals, not Ord('q'): the frontend does not fold Ord/Chr into a
    constant yet, so they cannot be case labels — compat-pascal-const-expr-ord-chr-succ. }
  case KeyCode of
    113, 81, 65307:   { 'q' 'Q' GDK Escape }
      gtk_main_quit;
    114, 82:          { 'r' 'R' — reset view }
      begin FCx := -0.75; FCy := 0.0; FSpan := 3.2; FMaxIt := MAXIT_DEF; Invalidate; end;
    43, 61:           { '+' '=' }
      begin FSpan := FSpan * 0.5; Invalidate; end;
    45, 95:           { '-' '_' }
      begin FSpan := FSpan * 2.0; Invalidate; end;
    91:               { '[' — fewer iterations }
      begin FMaxIt := FMaxIt div 2; if FMaxIt < 40 then FMaxIt := 40; Invalidate; end;
    93:               { ']' — more iterations }
      begin FMaxIt := FMaxIt * 2; if FMaxIt > 20000 then FMaxIt := 20000; Invalidate; end;
  end;
end;

procedure TMandelHandler.DoResize(Sender: TControl; Width, Height: Integer);
var w, h: Integer;
begin
  w := Width - 20; h := Height - 60;
  if w < 32 then w := 32;
  if h < 32 then h := 32;
  if (w = FBitmap.Width) and (h = FBitmap.Height) then Exit;
  FBitmap.Width := w;
  FBitmap.Height := h;
  SetLength(fb, w * h);
  Invalidate;
end;

{ ---------------- smoke: bounded, offscreen, no window ---------------- }

procedure RunSmoke;
var t0, usPar, usSer, sumPar, sumSer: Int64; i: Integer;
begin
  InitMandelKernel;
  BuildPalette;
  SetLength(fb, SMOKE_W * SMOKE_H);
  gW := SMOKE_W; gH := SMOKE_H; gMaxIt := MAXIT_DEF; gStep := 1;
  gCx := -0.75; gCy := 0.0; gSpanRe := 3.2;
  gSpanIm := 3.2 * (SMOKE_H / SMOKE_W);

  t0 := NowUsec; RenderFrame; usPar := NowUsec - t0;
  sumPar := 0;
  for i := 0 to SMOKE_W * SMOKE_H - 1 do sumPar := sumPar + fb[i];

  PXXSetParForWorkers(1);
  t0 := NowUsec; RenderFrame; usSer := NowUsec - t0;
  PXXSetParForWorkers(0);

  sumSer := 0;
  for i := 0 to SMOKE_W * SMOKE_H - 1 do sumSer := sumSer + fb[i];

  if usPar <= 0 then usPar := 1;
  if usSer <= 0 then usSer := 1;

  writeln('mandelbrot_gui smoke  ', SMOKE_W, 'x', SMOKE_H, '  it=', MAXIT_DEF);
  writeln('  cpu can do : ', ISAName(DetectISA));
  writeln('  build uses : ', ISAName(ActiveISA));
  writeln('  workers    : ', PXXParForWorkers);
  writeln('  serial     : ', usSer, ' us');
  writeln('  parallel   : ', usPar, ' us   speedup ', (usSer * 100) div usPar, ' /100x');
  writeln('  checksum   : ', sumPar);
  if sumPar <> sumSer then
  begin
    writeln('  MISMATCH — serial ', sumSer, ' vs parallel ', sumPar,
            ' (BUG: the render is not partition-independent)');
    Halt(1);
  end;
  writeln('  serial == parallel — OK');
end;

{ ---------------- main ---------------- }

var
  Form1: TForm;
  PaintBox: TPaintBox;
  Status: TLabel;
  Handler: TMandelHandler;
  guiSmoke: Boolean;

begin
  guiSmoke := False;
  if ParamCount >= 1 then
  begin
    if ParamStr(1) = '--smoke' then begin RunSmoke; Halt(0); end
    else if ParamStr(1) = '--gui-smoke' then guiSmoke := True
    else begin writeln('usage: mandelbrot_gui [--smoke | --gui-smoke]'); Halt(2); end;
  end;

  InitMandelKernel;
  BuildPalette;

  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'PXX Mandelbrot — tiled, multithreaded';
  Form1.Width := INIT_W + 20;
  Form1.Height := INIT_H + 60;

  PaintBox := TPaintBox.Create(nil);
  PaintBox.Parent := Form1;
  PaintBox.Left := 10;
  PaintBox.Top := 10;
  PaintBox.Width := INIT_W;
  PaintBox.Height := INIT_H;

  Status := TLabel.Create(nil);
  Status.Parent := Form1;
  Status.Left := 10;
  Status.Top := INIT_H + 20;
  Status.Width := INIT_W;
  Status.Height := 24;
  Status.Caption := 'rendering...';

  Handler := TMandelHandler.Create(PaintBox, Status);

  PaintBox.OnPaint := @Handler.OnPaint;
  PaintBox.OnMouseDown := @Handler.DoMouseDown;
  PaintBox.OnMouseUp := @Handler.DoMouseUp;
  PaintBox.OnMouseMove := @Handler.DoMouseMove;
  PaintBox.OnKeyDown := @Handler.DoKeyDown;
  Form1.OnKeyDown := @Handler.DoKeyDown;
  Form1.OnResize := @Handler.DoResize;

  Handler.Invalidate;

  if guiSmoke then g_timeout_add(6000, @GuiAutoQuit, nil);

  Application.MainForm := Form1;
  Application.Run;

  Handler.Destroy;
end.
