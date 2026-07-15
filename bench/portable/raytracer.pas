{ SPDX-License-Identifier: 0BSD }
program RaytracerPortable;
{ FPC-comparable variant of examples/raytracer/raytracer.pas — the float-heavy,
  call-dense inner loop with NO pxx-only units, so the bench `fpc` level can time
  it against the reference compiler.

  Same fixed scene, same Double kernel, same positional pixel CHECKSUM as the
  demo — the checksum is what makes the timing legitimate: (near-)same number =>
  same work was done. It self-checks against a pinned EXPECTED before it is worth
  timing, and Halt(1)s if the checksum lands OUTSIDE a tolerance band (the bench's
  `fpc` canary gates on EXIT CODE only, since the two RTLs format floats
  differently even when both are correct — so correctness must live in the exit
  code, not stdout).

  Why a tolerance band and not an exact match: pxx and FPC are two independent
  compilers and produce float results that differ by a ULP or two on the same
  source — association order, whether a*b+c is fused, x87-vs-SSE intermediates.
  Here that is ~0.05% of the checksum (a handful of pixels landing on opposite
  sides of a Trunc rounding boundary). That is not "different work" — same
  algorithm, same iteration counts — so the band accepts it while still catching
  a real codegen regression (garbage output moves the checksum by orders of
  magnitude, not 0.05%). The pxx levels themselves (-O0/-O2/-O3) still agree
  EXACTLY with each other; the band only exists to span the pxx<->FPC gap.

  Two departures from the demo, neither touching the arithmetic being measured:

    * specular ndh^32 by repeated squaring, not Power(). Keeps the timed inner
      loop pure codegen — a benchmark should time our multiplies, not the RTL's
      transcendental Power (exp/ln). Five multiplies.
    * plane floor is an inline integer floor, not math.Floor — no return-width
      ambiguity.

  Only `math` is used, for Sqrt (hardware sqrtsd — correctly rounded and
  identical on pxx and FPC, so it does not move the checksum); it is the one unit
  both compilers ship (nbody uses it too). Everything else (Abs, arg parsing via
  Val, integer writeln) is a builtin. Track T bench fixture, NOT a replacement
  for the demo, which stays idiomatic and exists to use our image/png libraries. }

uses math;

const
  SMOKE_W  = 96;
  SMOKE_H  = 64;
  MAXDEPTH = 3;
  INF      = 1.0e30;
  EPS      = 0.0001;
  EXPECTED = 297858362;  { SMOKE_W x SMOKE_H pixel checksum (pxx). FPC lands at
                           297697376 — 0.05% off, within TOL below. }
  TOL      = EXPECTED div 500;   { 0.2% band: spans the pxx<->FPC float gap
                                   (~0.05%) with margin, still orders of
                                   magnitude tighter than any real regression. }

type
  Vec3 = record x, y, z: Double; end;

  TSphere = record
    c: Vec3;              { centre }
    r: Double;            { radius }
    col: Vec3;            { albedo 0..1 }
    refl: Double;         { mirror term 0..1 }
  end;

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

{ Integer floor of a Double — inline, no math unit. }
function IFloor(x: Double): Integer;
var i: Integer;
begin
  i := Trunc(x);
  if (x < 0.0) and (x <> i) then i := i - 1;
  IFloor := i;
end;

function PlaneColor(const p: Vec3): Vec3;
var ix, iz: Integer;
begin
  ix := IFloor(p.x);
  iz := IFloor(p.z);
  if ((ix + iz) and 1) = 0 then PlaneColor := V(0.9, 0.9, 0.9)
  else PlaneColor := V(0.2, 0.2, 0.2);
end;

{ True if any object blocks the segment from p toward the light. }
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
  hitKind, hitIdx, k: Integer;   { 0 none, 1 sphere, 2 plane }
  p, n, ld, vdir, h, base, col, refllcol: Vec3;
  diff, spec, ndl, ndh: Double;
  s2, s4, s8, s16: Double;
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
      if ndh > 0.0 then
      begin
        { ndh^32 by repeated squaring — bit-identical on pxx and FPC, unlike
          Power(ndh, 32.0), whose transcendental path differs by ULPs and would
          move the checksum apart between the two compilers. }
        s2  := ndh * ndh;
        s4  := s2 * s2;
        s8  := s4 * s4;
        s16 := s8 * s8;
        spec := s16 * s16;
      end;
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

{ Trace every pixel and fold the RGB into the positional checksum. No image
  buffer, no PPM — the arithmetic under measurement is the tracing, not the
  storage, and the checksum captures that the same pixels came out. }
function RenderChecksum(iw, ih: Integer): Int64;
var
  px, py: Integer;
  sx, sy, aspect, fov: Double;
  ro, rd, col: Vec3;
  r, g, b: Integer;
  checksum: Int64;
begin
  aspect := iw / ih;
  fov := 1.0;
  checksum := 0;
  ro := V(0.0, 1.0, 0.0);     { camera a touch above the plane }

  for py := 0 to ih - 1 do
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
    end;

  RenderChecksum := checksum;
end;

var
  iw, ih, code: Integer;
  csum: Int64;
begin
  iw := SMOKE_W; ih := SMOKE_H;
  if ParamCount >= 2 then
  begin
    Val(ParamStr(1), iw, code); if code <> 0 then iw := SMOKE_W;
    Val(ParamStr(2), ih, code); if code <> 0 then ih := SMOKE_H;
  end;

  BuildScene;
  csum := RenderChecksum(iw, ih);
  writeln('checksum=', csum);

  { Self-check only at the pinned smoke size; timed runs use a larger frame.
    Tolerance band, not exact — see the header note on pxx<->FPC float drift. }
  if (iw = SMOKE_W) and (ih = SMOKE_H) then
  begin
    if Abs(csum - EXPECTED) <= TOL then writeln('ALL OK')
    else begin writeln('FAILURES (want ', EXPECTED, ' +/- ', TOL, ')'); Halt(1); end;
  end;
end.
