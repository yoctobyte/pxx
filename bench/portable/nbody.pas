{ SPDX-License-Identifier: 0BSD }
program NBody;
{ Portable N-body integrator — the common Pascal subset BOTH pascal26 and FPC
  accept, so it is a fair codegen benchmark across compilers (bench.tsv `fpc`
  level) and across -O levels. Deterministic: prints the system energy as a
  fixed-format Double so the canary (output equality) holds pxx-vs-fpc and
  -O0-vs-O2-vs-O3. Only the `math` unit (Sqrt), which both RTLs provide. }

uses math;

const
  N     = 5;
  Steps = 200000;
  DT    = 0.01;

type
  TVec = record x, y, z: Double; end;

var
  pos, vel: array[1..N] of TVec;
  mass: array[1..N] of Double;
  i, j, s: LongInt;
  dx, dy, dz, d2, dist, mag, e: Double;

procedure Init;
begin
  { Sun + four bodies — arbitrary but fixed initial conditions. }
  pos[1].x := 0;    pos[1].y := 0;    pos[1].z := 0;
  pos[2].x := 1;    pos[2].y := 0;    pos[2].z := 0;
  pos[3].x := 0;    pos[3].y := 1.3;  pos[3].z := 0;
  pos[4].x := -1.1; pos[4].y := 0;    pos[4].z := 0.4;
  pos[5].x := 0;    pos[5].y := -1.2; pos[5].z := -0.3;
  for i := 1 to N do
  begin
    vel[i].x := 0; vel[i].y := 0; vel[i].z := 0;
    mass[i] := 1.0;
  end;
  mass[1] := 100.0;
end;

begin
  Init;
  for s := 1 to Steps do
  begin
    for i := 1 to N do
      for j := 1 to N do
        if i <> j then
        begin
          dx := pos[j].x - pos[i].x;
          dy := pos[j].y - pos[i].y;
          dz := pos[j].z - pos[i].z;
          d2 := dx*dx + dy*dy + dz*dz + 0.001;
          dist := Sqrt(d2);
          mag := DT * mass[j] / (d2 * dist);
          vel[i].x := vel[i].x + dx * mag;
          vel[i].y := vel[i].y + dy * mag;
          vel[i].z := vel[i].z + dz * mag;
        end;
    for i := 1 to N do
    begin
      pos[i].x := pos[i].x + DT * vel[i].x;
      pos[i].y := pos[i].y + DT * vel[i].y;
      pos[i].z := pos[i].z + DT * vel[i].z;
    end;
  end;

  e := 0;
  for i := 1 to N do
    e := e + vel[i].x*vel[i].x + vel[i].y*vel[i].y + vel[i].z*vel[i].z;
  Writeln('energy ', (e*1000):0:0);
end.
