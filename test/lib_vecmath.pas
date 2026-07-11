program lib_vecmath;

{ Golden test for lib/rtl/vecmath.pas — integer-valued identities so the
  expected strings are exact (FP-determinism rules). Doubles as an operator
  overloading workout: several record types sharing the same operator
  symbols, chained expressions, operators used inside the unit's own
  functions (Lerp uses + - *). }

uses vecmath;

procedure P2(const tag: string; const v: TVec2);
begin
  writeln(tag, '=', v.x:1:2, ' ', v.y:1:2);
end;

procedure P3(const tag: string; const v: TVec3);
begin
  writeln(tag, '=', v.x:1:2, ' ', v.y:1:2, ' ', v.z:1:2);
end;

procedure P4(const tag: string; const v: TVec4);
begin
  writeln(tag, '=', v.x:1:2, ' ', v.y:1:2, ' ', v.z:1:2, ' ', v.w:1:2);
end;

var
  a3, b3, c3: TVec3;
  a2: TVec2;
  v4: TVec4;
  ma, mb, mc: TMat3;
  t4, s4, r4: TMat4;
  k: Integer;
  halfpi: Double;
begin
  { vec3 arithmetic + chain }
  a3 := Vec3(1.0, 2.0, 3.0);
  b3 := Vec3(4.0, 5.0, 6.0);
  P3('add', a3 + b3);                        { 5 7 9 }
  P3('sub', b3 - a3);                        { 3 3 3 }
  P3('mul', a3 * 2.0);                       { 2 4 6 }
  P3('div', b3 / 2.0);                       { 2 2.5 3 }
  P3('chain', (a3 + b3) * 2.0 - a3);         { 9 12 15 }

  { equality }
  if a3 + b3 = Vec3(5.0, 7.0, 9.0) then writeln('eq3=yes') else writeln('eq3=no');
  if not (a3 = b3) then writeln('neq3=yes') else writeln('neq3=no');

  { dot / cross / norms }
  writeln('dot3=', Dot3(a3, b3):1:2);        { 32 }
  P3('crossXY', Cross(Vec3(1.0, 0.0, 0.0), Vec3(0.0, 1.0, 0.0)));  { 0 0 1 }
  c3 := Cross(a3, b3);                       { (-3, 6, -3) }
  P3('cross', c3);
  writeln('orth1=', Dot3(c3, a3):1:2);       { 0 }
  writeln('orth2=', Dot3(c3, b3):1:2);       { 0 }
  a2 := Vec2(3.0, 4.0);
  writeln('norm2=', Norm2(a2):1:2);          { 5 }
  P2('normalize2', Normalize2(a2));          { 0.6 0.8 }
  writeln('normlen=', Norm2(Normalize2(a2)):1:2);   { 1 }
  P2('normzero', Normalize2(Vec2(0.0, 0.0)));       { 0 0 }

  { componentwise + lerp }
  P3('vmul3', VMul3(a3, b3));                { 4 10 18 }
  P3('lerp3', Lerp3(Vec3(0.0, 0.0, 0.0), Vec3(10.0, 20.0, 30.0), 0.5));  { 5 10 15 }

  { vec4 }
  v4 := Vec4(1.0, 2.0, 3.0, 4.0);
  P4('add4', v4 + v4);                       { 2 4 6 8 }
  writeln('dot4=', Dot4(v4, v4):1:2);        { 30 }
  writeln('normsq4=', NormSq4(v4):1:2);      { 30 }

  { mat3: identity, product, det, transpose }
  ma := Mat3Identity;
  for k := 0 to 8 do mb.m[k] := k + 1.0;     { [[1,2,3],[4,5,6],[7,8,9]] }
  mc := ma * mb;
  if mc = mb then writeln('matI=yes') else writeln('matI=no');
  mc := mb * mb;   { row0 = [30, 36, 42] }
  writeln('m3sq=', mc.m[0]:1:2, ' ', mc.m[1]:1:2, ' ', mc.m[2]:1:2);
  writeln('det3I=', Det3(ma):1:2);           { 1 }
  writeln('det3scale=', Det3(Mat3Scale(2.0, 3.0, 4.0)):1:2);  { 24 }
  mb.m[8] := 10.0;                           { [[1,2,3],[4,5,6],[7,8,10]] det=-3 }
  writeln('det3=', Det3(mb):1:2);
  mc := Transpose3(mb);
  writeln('trans3=', mc.m[1]:1:2, ' ', mc.m[3]:1:2);  { 4 2 }
  if Transpose3(Transpose3(mb)) = mb then writeln('transinv=yes') else writeln('transinv=no');

  { mat3 * vec3 }
  P3('mv3', MulMV3(mb, Vec3(1.0, 1.0, 1.0)));   { 6 15 25 }

  { mat4: translate, scale, rotate, det, chain }
  t4 := Mat4Translate(1.0, 2.0, 3.0);
  P4('tpoint', MulMV4(t4, Vec4(1.0, 1.0, 1.0, 1.0)));   { 2 3 4 1 }
  s4 := Mat4Scale(2.0, 3.0, 4.0);
  writeln('det4scale=', Det4(s4):1:2);       { 24 (w row stays 1) }
  writeln('det4I=', Det4(Mat4Identity):1:2); { 1 }
  { translate then scale, applied to a point: S*(T*p) = (S*T)*p }
  P4('st', MulMV4(s4 * t4, Vec4(1.0, 1.0, 1.0, 1.0)));  { 4 9 16 1 }
  halfpi := 1.5707963267948966;
  r4 := Mat4RotateZ(halfpi);
  P4('rotz', MulMV4(r4, Vec4(1.0, 0.0, 0.0, 1.0)));     { 0 1 0 1 }
  P4('rotx', MulMV4(Mat4RotateX(halfpi), Vec4(0.0, 1.0, 0.0, 1.0)));  { 0 0 1 1 }
  if Det4(t4 * s4) = Det4(t4) * Det4(s4) then writeln('detmul=yes') else writeln('detmul=no');
end.
