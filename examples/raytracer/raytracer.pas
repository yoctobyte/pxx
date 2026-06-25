program RayTracer;
{ Headless CPU ray tracer — a float-compute + records demo.

  Fixed deterministic scene (no RNG): three spheres on a checkerboard plane, one
  point light, ambient + Lambert diffuse + Blinn-ish specular, hard shadows, and
  up to MAXDEPTH mirror reflections. Camera at the origin looking down -Z.

  Modes (no args = the deterministic smoke: small render + integer CHECKSUM, so
  it can be a lib-test/demos gate):

    raytracer                    render SMOKE_W x SMOKE_H, print CHECKSUM oracle
    raytracer --ppm FILE [W H]   render a colour PPM (P3) image

  Determinism: the scene and camera are fixed and the maths is strict IEEE-754
  Double, so the integer pixel CHECKSUM is reproducible across targets (same
  contract as the mandelbrot demo). math.pas supplies Sqrt; everything else is
  +, -, *, / on Double. Track B; integer-deterministic gate + a real image for
  humans.

  Exercises: records passed/returned by value (Vec3 vector algebra), dynamic
  array of scene objects, bounded recursion for reflections, nested float loops,
  and integer image-buffer / PPM output. }

uses sysutils, math;

const
  SMOKE_W = 96;
  SMOKE_H = 64;
  MAXDEPTH = 3;
  INF      = 1.0e30;
  EPS      = 0.0001;
  EXPECTED = 297935246;   { SMOKE_W x SMOKE_H pixel checksum; x86-64 == aarch64 }

type
  Vec3 = record x, y, z: Double; end;

  TSphere = record
    c: Vec3;              { centre }
    r: Double;            { radius }
    col: Vec3;            { albedo 0..1 }
    refl: Double;         { mirror term 0..1 }
  end;

{ ---- vector algebra ----
  Inputs are `const` Vec3: idiomatic for non-mutated record inputs (signals
  no-write, lets the ABI pass by-ref) AND it is what lets nested composition like
  VAdd(VScale(V(..),s), ..) compile — a plain by-value record param >8 bytes
  still rejects a temporary argument (bug-plain-byvalue-record-param-temp).
  Builds + runs on x86-64 and aarch64 (checksum-identical); arm32 needs large
  aggregate results (feature-arm32-large-aggregate-result), i386 needs float
  params, so the cross gate stays mandelbrot-only. }
function V(x, y, z: Double): Vec3;
begin V.x := x; V.y := y; V.z := z; end;

function VAdd(const a, b: Vec3): Vec3;
begin VAdd := V(a.x + b.x, a.y + b.y, a.z + b.z); end;

function VSub(const a, b: Vec3): Vec3;
begin VSub := V(a.x - b.x, a.y - b.y, a.z - b.z); end;

function VScale(const a: Vec3; s: Double): Vec3;
begin VScale := V(a.x * s, a.y * s, a.z * s); end;

function VMulV(const a, b: Vec3): Vec3;   { component-wise (albedo * light) }
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

{ Sphere intersection: nearest positive t along ro+rd*t, or INF. }
function HitSphere(const s: TSphere; const ro, rd: Vec3): Double;
var oc: Vec3; b, c, disc, sq, t0, t1: Double;
begin
  oc := VSub(ro, s.c);
  b := 2.0 * VDot(oc, rd);
  c := VDot(oc, oc) - s.r * s.r;
  disc := b * b - 4.0 * c;          { a = 1 since rd normalised }
  if disc < 0.0 then begin HitSphere := INF; Exit; end;
  sq := Sqrt(disc);
  t0 := (-b - sq) * 0.5;
  t1 := (-b + sq) * 0.5;
  if t0 > EPS then HitSphere := t0
  else if t1 > EPS then HitSphere := t1
  else HitSphere := INF;
end;

{ Ground plane y = -1, checkerboard. Returns t or INF. }
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

{ True if any object blocks the segment from p toward the light. }
function InShadow(const p: Vec3): Boolean;
var ld: Vec3; dist, t, i: Integer; ldist: Double; rd: Vec3; k: Integer;
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
  hitKind, hitIdx, k: Integer;   { 0 none, 1 sphere, 2 plane }
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
    { sky gradient }
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

  { mirror reflection }
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

{ Render the scene; if path<>'' write a PPM, always return the pixel checksum. }
function Render(iw, ih: Integer; const path: AnsiString): Int64;
var
  f: Text;
  px, py: Integer;
  sx, sy, aspect, fov: Double;
  ro, rd, col: Vec3;
  r, g, b: Integer;
  checksum: Int64;
  line: AnsiString;
  toFile: Boolean;
begin
  toFile := path <> '';
  aspect := iw / ih;
  fov := 1.0;                 { tan(half-fov) ~ scene scale }
  checksum := 0;
  ro := V(0.0, 1.0, 0.0);     { camera a touch above the plane }

  if toFile then
  begin
    Assign(f, path); Rewrite(f);
    writeln(f, 'P3');
    writeln(f, IntToStr(iw) + ' ' + IntToStr(ih));
    writeln(f, '255');
  end;

  for py := 0 to ih - 1 do
  begin
    line := '';
    for px := 0 to iw - 1 do
    begin
      sx := (2.0 * ((px + 0.5) / iw) - 1.0) * aspect * fov;
      sy := (1.0 - 2.0 * ((py + 0.5) / ih)) * fov;
      rd := VNorm(V(sx, sy, -1.0));
      col := Trace(ro, rd, 0);
      r := Clamp255(col.x);
      g := Clamp255(col.y);
      b := Clamp255(col.z);
      checksum := checksum + (r + 2 * g + 3 * b) * (px + 1);
      if toFile then
        line := line + IntToStr(r) + ' ' + IntToStr(g) + ' ' + IntToStr(b) + ' ';
    end;
    if toFile then writeln(f, line);
  end;

  if toFile then Close(f);
  Render := checksum;
end;

var
  i, iw, ih: Integer;
  a, mode, ppmPath: AnsiString;
  csum: Int64;
begin
  mode := 'smoke';
  ppmPath := 'raytracer.ppm';
  iw := 320; ih := 240;

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
    end;
    i := i + 1;
  end;

  BuildScene;

  if mode = 'ppm' then
  begin
    csum := Render(iw, ih, ppmPath);
    writeln('wrote ', ppmPath, ' (', iw, 'x', ih, ')');
    writeln('checksum=', csum);
  end
  else
  begin
    csum := Render(SMOKE_W, SMOKE_H, '');
    writeln('checksum=', csum);
    if EXPECTED = 0 then writeln('(no EXPECTED pinned yet)')
    else if csum = EXPECTED then writeln('ALL OK')
    else writeln('FAILURES (want ', EXPECTED, ')');
  end;
end.
