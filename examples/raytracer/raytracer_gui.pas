program raytracer_gui;

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, graphics, math, sysutils, baseunix;

const
  MAXDEPTH = 3;
  INF      = 1.0e30;
  EPS      = 0.0001;

type
  Vec3 = record x, y, z: Double; end;

  TSphere = record
    c: Vec3;              { centre }
    r: Double;            { radius }
    col: Vec3;            { albedo 0..1 }
    refl: Double;         { mirror term 0..1 }
  end;

{ ---- vector algebra ---- }
function V(x, y, z: Double): Vec3;
begin V.x := x; V.y := y; V.z := z; end;

function VAdd(const a, b: Vec3): Vec3;
begin VAdd := V(a.x + b.x, a.y + b.y, a.z + b.z); end;

function VSub(const a, b: Vec3): Vec3;
begin VSub := V(a.x - b.x, a.y - b.y, a.z - b.z); end;

function VScale(const a: Vec3; s: Double): Vec3;
begin VScale := V(a.x * s, a.y * s, a.z * s); end;

function VMulV(const a, b: Vec3): Vec3;
begin VMulV := V(a.x * b.x, a.y * b.y, a.z * b.z); end;

function VDot(const a, b: Vec3): Double;
begin VDot := a.x * b.x + a.y * b.y + a.z * b.z; end;

function VLen(const a: Vec3): Double;
begin VLen := Sqrt(VDot(a, a)); end;

function VNorm(const a: Vec3): Vec3;
var l: Double;
begin
  l := VLen(a);
  if l < EPS then VNorm := a
  else VNorm := VScale(a, 1.0 / l);
end;

function VCross(const a, b: Vec3): Vec3;
begin
  VCross.x := a.y * b.z - a.z * b.y;
  VCross.y := a.z * b.x - a.x * b.z;
  VCross.z := a.x * b.y - a.y * b.x;
end;

{ ---- scene ---- }
var
  Spheres: array of TSphere;
  LightPos: Vec3;

procedure AddSphere(cx, cy, cz, rad, r, g, b, refl: Double);
var s: TSphere; n: Integer;
begin
  s.c := V(cx, cy, cz);
  s.r := rad;
  s.col := V(r, g, b);
  s.refl := refl;
  n := Length(Spheres);
  SetLength(Spheres, n + 1);
  Spheres[n] := s;
end;

procedure BuildScene;
begin
  SetLength(Spheres, 0);
  AddSphere( 0.0, 0.0, -4.0, 1.0,  0.9, 0.2, 0.2, 0.3);   { red }
  AddSphere( 2.1, 0.0, -5.5, 1.0,  0.2, 0.9, 0.3, 0.5);   { green, shinier }
  AddSphere(-2.1, 0.0, -5.5, 1.0,  0.3, 0.4, 0.9, 0.4);   { blue }
  LightPos := V(5.0, 6.0, -1.0);
end;

function HitSphere(const s: TSphere; const ro, rd: Vec3): Double;
var oc: Vec3; b, c, disc, sq, t0, t1: Double;
begin
  oc := VSub(ro, s.c);
  b := 2.0 * VDot(oc, rd);
  c := VDot(oc, oc) - s.r * s.r;
  disc := b * b - 4.0 * c;
  if disc < 0.0 then begin HitSphere := INF; Exit; end;
  sq := Sqrt(disc);
  t0 := (-b - sq) * 0.5;
  t1 := (-b + sq) * 0.5;
  if t0 > EPS then HitSphere := t0
  else if t1 > EPS then HitSphere := t1
  else HitSphere := INF;
end;

function HitPlane(const ro, rd: Vec3): Double;
var t: Double;
begin
  if Abs(rd.y) < EPS then begin HitPlane := INF; Exit; end;
  t := (-1.0 - ro.y) / rd.y;
  if t > EPS then HitPlane := t else HitPlane := INF;
end;

function PlaneColor(const p: Vec3): Vec3;
var ix, iz: Integer;
begin
  ix := Trunc(Floor(p.x));
  iz := Trunc(Floor(p.z));
  if ((ix + iz) and 1) = 0 then PlaneColor := V(0.9, 0.9, 0.9)
  else PlaneColor := V(0.2, 0.2, 0.2);
end;

function InShadow(const p: Vec3): Boolean;
var ld: Vec3; ldist: Double; rd: Vec3; k: Integer;
begin
  ld := VSub(LightPos, p);
  ldist := VLen(ld);
  rd := VNorm(ld);
  InShadow := False;
  for k := 0 to Length(Spheres) - 1 do
  begin
    if HitSphere(Spheres[k], p, rd) < ldist then begin InShadow := True; Exit; end;
  end;
end;

function Trace(const ro, rd: Vec3; depth: Integer): Vec3;
var
  nearest, t: Double;
  hitKind, hitIdx, k: Integer;
  p, n, ld, vdir, h, base, col, refllcol: Vec3;
  diff, spec, ndl, ndh: Double;
  reflDir: Vec3;
  amb: Double;
begin
  nearest := INF; hitKind := 0; hitIdx := -1;

  for k := 0 to Length(Spheres) - 1 do
  begin
    t := HitSphere(Spheres[k], ro, rd);
    if t < nearest then begin nearest := t; hitKind := 1; hitIdx := k; end;
  end;
  t := HitPlane(ro, rd);
  if t < nearest then begin nearest := t; hitKind := 2; end;

  if hitKind = 0 then
  begin
    diff := 0.5 * (rd.y + 1.0);
    Trace := VAdd(VScale(V(1.0, 1.0, 1.0), 1.0 - diff),
                  VScale(V(0.4, 0.6, 1.0), diff));
    Exit;
  end;

  p := VAdd(ro, VScale(rd, nearest));
  if hitKind = 1 then
  begin
    n := VNorm(VSub(p, Spheres[hitIdx].c));
    base := Spheres[hitIdx].col;
  end
  else
  begin
    n := V(0.0, 1.0, 0.0);
    base := PlaneColor(p);
  end;

  ld := VNorm(VSub(LightPos, p));
  amb := 0.15;
  diff := 0.0; spec := 0.0;
  if not InShadow(VAdd(p, VScale(n, EPS * 10.0))) then
  begin
    ndl := VDot(n, ld);
    if ndl > 0.0 then
    begin
      diff := ndl;
      vdir := VNorm(VScale(rd, -1.0));
      h := VNorm(VAdd(ld, vdir));
      ndh := VDot(n, h);
      if ndh > 0.0 then spec := Power(ndh, 32.0);
    end;
  end;

  col := VMulV(base, VScale(V(1.0, 1.0, 1.0), amb + diff));
  col := VAdd(col, VScale(V(1.0, 1.0, 1.0), spec));

  if (hitKind <> 0) and (depth < MAXDEPTH) then
  begin
    if (hitKind = 1) and (Spheres[hitIdx].refl > 0.0) then
    begin
      reflDir := VNorm(VSub(rd, VScale(n, 2.0 * VDot(rd, n))));
      refllcol := Trace(VAdd(p, VScale(reflDir, EPS * 10.0)), reflDir, depth + 1);
      col := VAdd(VScale(col, 1.0 - Spheres[hitIdx].refl),
                  VScale(refllcol, Spheres[hitIdx].refl));
    end;
  end;

  Trace := col;
end;

function Clamp255(v: Double): Integer;
var i: Integer;
begin
  i := Trunc(v * 255.0 + 0.5);
  if i < 0 then i := 0;
  if i > 255 then i := 255;
  Clamp255 := i;
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then
    NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else
    NowUsec := 0;
end;

type
  TRaytracerHandler = class
  private
    FBitmap: TBitmap;
    FPaintBox: TPaintBox;
    FStatusLabel: TLabel;
    FDragging: Boolean;
    FDragButton: Integer;
    FLastMouseX: Integer;
    FLastMouseY: Integer;

    FTarget: Vec3;
    FTheta: Double;
    FPhi: Double;
    FRadius: Double;

    FInteractive: Boolean;
    FDownscale: Integer;

    procedure RenderToBitmap;
  public
    constructor Create(APaintBox: TPaintBox; AStatusLabel: TLabel);
    destructor Destroy;

    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure DoMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseMove(Sender: TControl; Button, X, Y: Integer);
    procedure DoKeyDown(Sender: TControl; KeyCode: Integer);
    procedure DoResize(Sender: TControl; Width, Height: Integer);

    procedure SetInteractive(AInteractive: Boolean);
    procedure Render;
  end;

constructor TRaytracerHandler.Create(APaintBox: TPaintBox; AStatusLabel: TLabel);
begin
  FPaintBox := APaintBox;
  FStatusLabel := AStatusLabel;
  FDragging := False;
  FInteractive := False;
  FDownscale := 4;

  FTarget := V(0.0, 0.0, -4.0);
  FTheta := 3.14159265 * 1.5;
  FPhi := 0.24;
  FRadius := 4.12;

  FBitmap := TBitmap.Create;
  FBitmap.Width := 640;
  FBitmap.Height := 480;
  FBitmap.Clear($00000000);
end;

destructor TRaytracerHandler.Destroy;
begin
  FBitmap.Destroy;
end;

procedure TRaytracerHandler.SetInteractive(AInteractive: Boolean);
begin
  if FInteractive <> AInteractive then
  begin
    FInteractive := AInteractive;
    Self.Render;
  end;
end;

procedure TRaytracerHandler.RenderToBitmap;
var
  iw, ih, px, py, subx, suby, ds: Integer;
  aspect, fov, sx, sy: Double;
  ro, rd, col, u, v, w: Vec3;
  color: TColor;
  t0, t1: Int64;
begin
  t0 := NowUsec;
  iw := FBitmap.Width;
  ih := FBitmap.Height;
  if (iw <= 0) or (ih <= 0) then Exit;

  aspect := iw / ih;
  fov := 1.0;

  ro.x := FTarget.x + FRadius * Cos(FTheta) * Cos(FPhi);
  ro.y := FTarget.y + FRadius * Sin(FPhi);
  ro.z := FTarget.z + FRadius * Sin(FTheta) * Cos(FPhi);

  w := VNorm(VSub(ro, FTarget));
  u := VNorm(VCross(V(0.0, 1.0, 0.0), w));
  v := VCross(w, u);

  if FInteractive then
    ds := FDownscale
  else
    ds := 1;

  py := 0;
  while py < ih do
  begin
    px := 0;
    while px < iw do
    begin
      sx := (2.0 * ((px + 0.5) / iw) - 1.0) * aspect * fov;
      sy := (1.0 - 2.0 * ((py + 0.5) / ih)) * fov;

      rd := VNorm(VAdd(VAdd(VScale(u, sx), VScale(v, sy)), VScale(w, -1.0)));
      col := Trace(ro, rd, 0);

      color := (Clamp255(col.z) shl 16) or (Clamp255(col.y) shl 8) or Clamp255(col.x);

      if ds > 1 then
      begin
        for suby := 0 to ds - 1 do
          for subx := 0 to ds - 1 do
            if (px + subx < iw) and (py + suby < ih) then
              FBitmap.SetPixel(px + subx, py + suby, color);
      end
      else
        FBitmap.SetPixel(px, py, color);

      px := px + ds;
    end;
    py := py + ds;
  end;

  t1 := NowUsec;
  FStatusLabel.Caption := 'Render Time: ' + IntToStr((t1 - t0) div 1000) + 'ms | Camera: (' + FloatToStrF(ro.x, 2) + ', ' + FloatToStrF(ro.y, 2) + ', ' + FloatToStrF(ro.z, 2) + ') | Zoom Radius: ' + FloatToStrF(FRadius, 2);
end;

procedure TRaytracerHandler.Render;
begin
  Self.RenderToBitmap;
  FPaintBox.Invalidate;
end;

procedure TRaytracerHandler.OnPaint(Sender: TControl; Canvas: TCanvas);
begin
  Canvas.Draw(0, 0, FBitmap);
end;

procedure TRaytracerHandler.DoMouseDown(Sender: TControl; Button, X, Y: Integer);
begin
  FDragging := True;
  FDragButton := Button;
  FLastMouseX := X;
  FLastMouseY := Y;
  FInteractive := True;
end;

procedure TRaytracerHandler.DoMouseUp(Sender: TControl; Button, X, Y: Integer);
begin
  if FDragging then
  begin
    FDragging := False;
    FInteractive := False;
    Self.Render;
  end;
end;

procedure TRaytracerHandler.DoMouseMove(Sender: TControl; Button, X, Y: Integer);
var
  dx, dy: Integer;
  ro, w, u, v: Vec3;
begin
  if FDragging then
  begin
    dx := X - FLastMouseX;
    dy := Y - FLastMouseY;
    FLastMouseX := X;
    FLastMouseY := Y;

    if FDragButton = 1 then
    begin
      FTheta := FTheta - dx * 0.005;
      FPhi := FPhi + dy * 0.005;
      if FPhi > 1.4 then FPhi := 1.4;
      if FPhi < -1.4 then FPhi := -1.4;
    end
    else if FDragButton = 3 then
    begin
      ro.x := FTarget.x + FRadius * Cos(FTheta) * Cos(FPhi);
      ro.y := FTarget.y + FRadius * Sin(FPhi);
      ro.z := FTarget.z + FRadius * Sin(FTheta) * Cos(FPhi);
      w := VNorm(VSub(ro, FTarget));
      u := VNorm(VCross(V(0.0, 1.0, 0.0), w));
      v := VCross(w, u);

      FTarget := VAdd(FTarget, VAdd(VScale(u, -dx * 0.005 * FRadius), VScale(v, dy * 0.005 * FRadius)));
    end;

    Self.Render;
  end;
end;

procedure TRaytracerHandler.DoKeyDown(Sender: TControl; KeyCode: Integer);
begin
  if (KeyCode = 61) or (KeyCode = 65451) or (KeyCode = ord('+')) then
  begin
    FRadius := FRadius * 0.9;
    Self.Render;
  end
  else if (KeyCode = 45) or (KeyCode = 65453) or (KeyCode = ord('-')) then
  begin
    FRadius := FRadius * 1.1;
    Self.Render;
  end
  else if (KeyCode = 65362) or (KeyCode = ord('w')) or (KeyCode = ord('W')) then
  begin
    FPhi := FPhi + 0.05;
    if FPhi > 1.4 then FPhi := 1.4;
    Self.Render;
  end
  else if (KeyCode = 65364) or (KeyCode = ord('s')) or (KeyCode = ord('S')) then
  begin
    FPhi := FPhi - 0.05;
    if FPhi < -1.4 then FPhi := -1.4;
    Self.Render;
  end
  else if (KeyCode = 65361) or (KeyCode = ord('a')) or (KeyCode = ord('A')) then
  begin
    FTheta := FTheta - 0.05;
    Self.Render;
  end
  else if (KeyCode = 65363) or (KeyCode = ord('d')) or (KeyCode = ord('D')) then
  begin
    FTheta := FTheta + 0.05;
    Self.Render;
  end
  else if (KeyCode = 113) or (KeyCode = 81) or (KeyCode = 65307) then
  begin
    gtk_main_quit;
  end;
end;

procedure TRaytracerHandler.DoResize(Sender: TControl; Width, Height: Integer);
begin
  if (Width > 20) and (Height > 50) then
  begin
    FPaintBox.SetBounds(10, 10, Width - 20, Height - 50);
    FStatusLabel.SetBounds(10, Height - 35, Width - 20, 25);
    FBitmap.Width := Width - 20;
    FBitmap.Height := Height - 50;
    Self.Render;
  end;
end;

function AutoQuit(data: Pointer): Integer; cdecl;
var
  h: TRaytracerHandler;
begin
  h := TRaytracerHandler(data);
  writeln('Smoke test auto-quit.');
  gtk_main_quit;
  AutoQuit := 0;
end;

var
  Form1: TForm;
  PaintBox: TPaintBox;
  StatusLabel: TLabel;
  Handler: TRaytracerHandler;
  arg: string;

begin
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'PXX CPU Ray Tracer';
  Form1.SetBounds(100, 100, 660, 560);

  PaintBox := TPaintBox.Create(nil);
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(10, 10, 640, 480);

  StatusLabel := TLabel.Create(nil);
  StatusLabel.Parent := Form1;
  StatusLabel.Caption := 'Initializing...';
  StatusLabel.SetBounds(10, 500, 640, 25);

  BuildScene;

  Handler := TRaytracerHandler.Create(PaintBox, StatusLabel);

  PaintBox.OnPaint := @Handler.OnPaint;
  PaintBox.OnMouseDown := @Handler.DoMouseDown;
  PaintBox.OnMouseUp := @Handler.DoMouseUp;
  PaintBox.OnMouseMove := @Handler.DoMouseMove;
  Form1.OnKeyDown := @Handler.DoKeyDown;
  PaintBox.OnKeyDown := @Handler.DoKeyDown;
  Form1.OnResize := @Handler.DoResize;

  Handler.Render;

  if ParamCount > 0 then
  begin
    arg := ParamStr(1);
    if arg = '--smoke' then
    begin
      writeln('Running in smoke-test mode...');
      g_timeout_add(1000, @AutoQuit, Pointer(Handler));
    end;
  end;

  Application.MainForm := Form1;
  Application.Run;

  Handler.Destroy;
end.
