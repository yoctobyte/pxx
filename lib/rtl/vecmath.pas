unit vecmath;

{ Vector/matrix math for demos, games and GUI code (Track B), and a workout
  for record operator overloading. Doubles throughout; matrices are flat
  row-major arrays (TMat3: m[r*3+c], TMat4: m[r*4+c]).

  pxx dialect notes (see bug-overload-resolution-record-identity and
  feature-pascal-operator-decl-fpc-compat):
  - Operator overload dispatch keys on the LEFT operand's record type, ONE
    overload per operator per type. So per vec type: `+ - ` are vec op vec,
    `* /` are vec op SCALAR; componentwise product is VMul. For
    matrices `*` is mat*mat; matrix-vector product is MulMV.
    scalar*vec (scalar on the left) is not registrable — write v * s.
  - Functions overload cleanly on record identity (Dot/Norm/Lerp/... for
    TVec2/3/4) since bug-overload-resolution-record-identity was fixed. }

interface

uses math;

type
  TVec2 = record
    x, y: Double;
  end;
  TVec3 = record
    x, y, z: Double;
  end;
  TVec4 = record
    x, y, z, w: Double;
  end;
  TMat3 = record
    m: array[0..8] of Double;    { row-major: m[r*3+c] }
  end;
  TMat4 = record
    m: array[0..15] of Double;   { row-major: m[r*4+c] }
  end;

{ vector operators: vec op vec for + - =, vec op scalar for * / }
operator + (a, b: TVec2) r: TVec2;
operator - (a, b: TVec2) r: TVec2;
operator * (a: TVec2; s: Double) r: TVec2;
operator / (a: TVec2; s: Double) r: TVec2;
operator = (a, b: TVec2) eq: Boolean;

operator + (a, b: TVec3) r: TVec3;
operator - (a, b: TVec3) r: TVec3;
operator * (a: TVec3; s: Double) r: TVec3;
operator / (a: TVec3; s: Double) r: TVec3;
operator = (a, b: TVec3) eq: Boolean;

operator + (a, b: TVec4) r: TVec4;
operator - (a, b: TVec4) r: TVec4;
operator * (a: TVec4; s: Double) r: TVec4;
operator / (a: TVec4; s: Double) r: TVec4;
operator = (a, b: TVec4) eq: Boolean;

{ matrix operators: mat*mat; use MulMV for mat*vec }
operator + (a, b: TMat3) r: TMat3;
operator - (a, b: TMat3) r: TMat3;
operator * (a, b: TMat3) r: TMat3;
operator = (a, b: TMat3) eq: Boolean;

operator + (a, b: TMat4) r: TMat4;
operator - (a, b: TMat4) r: TMat4;
operator * (a, b: TMat4) r: TMat4;
operator = (a, b: TMat4) eq: Boolean;

{ constructors }
function Vec2(ax, ay: Double): TVec2;
function Vec3(ax, ay, az: Double): TVec3;
function Vec4(ax, ay, az, aw: Double): TVec4;

{ vector functions }
function Dot(const a, b: TVec2): Double;
function Dot(const a, b: TVec3): Double;
function Dot(const a, b: TVec4): Double;
function Cross(const a, b: TVec3): TVec3;
function VMul(const a, b: TVec2): TVec2;    { componentwise product }
function VMul(const a, b: TVec3): TVec3;
function VMul(const a, b: TVec4): TVec4;
function NormSq(const a: TVec2): Double;
function NormSq(const a: TVec3): Double;
function NormSq(const a: TVec4): Double;
function Norm(const a: TVec2): Double;
function Norm(const a: TVec3): Double;
function Norm(const a: TVec4): Double;
function Normalize(const a: TVec2): TVec2;
function Normalize(const a: TVec3): TVec3;
function Normalize(const a: TVec4): TVec4;
function Lerp(const a, b: TVec2; t: Double): TVec2;
function Lerp(const a, b: TVec3; t: Double): TVec3;
function Lerp(const a, b: TVec4; t: Double): TVec4;

{ matrix functions }
function Mat3Identity: TMat3;
function Mat4Identity: TMat4;
function Mat3Scale(sx, sy, sz: Double): TMat3;
function Mat4Scale(sx, sy, sz: Double): TMat4;
function Mat4Translate(tx, ty, tz: Double): TMat4;
function Mat3RotateZ(angle: Double): TMat3;
function Mat4RotateX(angle: Double): TMat4;
function Mat4RotateY(angle: Double): TMat4;
function Mat4RotateZ(angle: Double): TMat4;
function Transpose(const a: TMat3): TMat3;
function Transpose(const a: TMat4): TMat4;
function Det(const a: TMat3): Double;
function Det(const a: TMat4): Double;
function MulMV(const a: TMat3; const v: TVec3): TVec3;
function MulMV(const a: TMat4; const v: TVec4): TVec4;

implementation

{ ---- TVec2 ---- }

operator + (a, b: TVec2) r: TVec2;
begin
  r.x := a.x + b.x;
  r.y := a.y + b.y;
end;

operator - (a, b: TVec2) r: TVec2;
begin
  r.x := a.x - b.x;
  r.y := a.y - b.y;
end;

operator * (a: TVec2; s: Double) r: TVec2;
begin
  r.x := a.x * s;
  r.y := a.y * s;
end;

operator / (a: TVec2; s: Double) r: TVec2;
begin
  r.x := a.x / s;
  r.y := a.y / s;
end;

operator = (a, b: TVec2) eq: Boolean;
begin
  eq := (a.x = b.x) and (a.y = b.y);
end;

{ ---- TVec3 ---- }

operator + (a, b: TVec3) r: TVec3;
begin
  r.x := a.x + b.x;
  r.y := a.y + b.y;
  r.z := a.z + b.z;
end;

operator - (a, b: TVec3) r: TVec3;
begin
  r.x := a.x - b.x;
  r.y := a.y - b.y;
  r.z := a.z - b.z;
end;

operator * (a: TVec3; s: Double) r: TVec3;
begin
  r.x := a.x * s;
  r.y := a.y * s;
  r.z := a.z * s;
end;

operator / (a: TVec3; s: Double) r: TVec3;
begin
  r.x := a.x / s;
  r.y := a.y / s;
  r.z := a.z / s;
end;

operator = (a, b: TVec3) eq: Boolean;
begin
  eq := (a.x = b.x) and (a.y = b.y) and (a.z = b.z);
end;

{ ---- TVec4 ---- }

operator + (a, b: TVec4) r: TVec4;
begin
  r.x := a.x + b.x;
  r.y := a.y + b.y;
  r.z := a.z + b.z;
  r.w := a.w + b.w;
end;

operator - (a, b: TVec4) r: TVec4;
begin
  r.x := a.x - b.x;
  r.y := a.y - b.y;
  r.z := a.z - b.z;
  r.w := a.w - b.w;
end;

operator * (a: TVec4; s: Double) r: TVec4;
begin
  r.x := a.x * s;
  r.y := a.y * s;
  r.z := a.z * s;
  r.w := a.w * s;
end;

operator / (a: TVec4; s: Double) r: TVec4;
begin
  r.x := a.x / s;
  r.y := a.y / s;
  r.z := a.z / s;
  r.w := a.w / s;
end;

operator = (a, b: TVec4) eq: Boolean;
begin
  eq := (a.x = b.x) and (a.y = b.y) and (a.z = b.z) and (a.w = b.w);
end;

{ ---- TMat3 ---- }

operator + (a, b: TMat3) r: TMat3;
var k: Integer;
begin
  for k := 0 to 8 do r.m[k] := a.m[k] + b.m[k];
end;

operator - (a, b: TMat3) r: TMat3;
var k: Integer;
begin
  for k := 0 to 8 do r.m[k] := a.m[k] - b.m[k];
end;

operator * (a, b: TMat3) r: TMat3;
var row, col, k: Integer; acc: Double;
begin
  for row := 0 to 2 do
    for col := 0 to 2 do
    begin
      acc := 0.0;
      for k := 0 to 2 do
        acc := acc + a.m[row * 3 + k] * b.m[k * 3 + col];
      r.m[row * 3 + col] := acc;
    end;
end;

operator = (a, b: TMat3) eq: Boolean;
var k: Integer;
begin
  eq := True;
  for k := 0 to 8 do
    if a.m[k] <> b.m[k] then eq := False;
end;

{ ---- TMat4 ---- }

operator + (a, b: TMat4) r: TMat4;
var k: Integer;
begin
  for k := 0 to 15 do r.m[k] := a.m[k] + b.m[k];
end;

operator - (a, b: TMat4) r: TMat4;
var k: Integer;
begin
  for k := 0 to 15 do r.m[k] := a.m[k] - b.m[k];
end;

operator * (a, b: TMat4) r: TMat4;
var row, col, k: Integer; acc: Double;
begin
  for row := 0 to 3 do
    for col := 0 to 3 do
    begin
      acc := 0.0;
      for k := 0 to 3 do
        acc := acc + a.m[row * 4 + k] * b.m[k * 4 + col];
      r.m[row * 4 + col] := acc;
    end;
end;

operator = (a, b: TMat4) eq: Boolean;
var k: Integer;
begin
  eq := True;
  for k := 0 to 15 do
    if a.m[k] <> b.m[k] then eq := False;
end;

{ ---- constructors ---- }

function Vec2(ax, ay: Double): TVec2;
begin
  Result.x := ax; Result.y := ay;
end;

function Vec3(ax, ay, az: Double): TVec3;
begin
  Result.x := ax; Result.y := ay; Result.z := az;
end;

function Vec4(ax, ay, az, aw: Double): TVec4;
begin
  Result.x := ax; Result.y := ay; Result.z := az; Result.w := aw;
end;

{ ---- vector functions ---- }

function Dot(const a, b: TVec2): Double;
begin
  Result := a.x * b.x + a.y * b.y;
end;

function Dot(const a, b: TVec3): Double;
begin
  Result := a.x * b.x + a.y * b.y + a.z * b.z;
end;

function Dot(const a, b: TVec4): Double;
begin
  Result := a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
end;

function Cross(const a, b: TVec3): TVec3;
begin
  Result.x := a.y * b.z - a.z * b.y;
  Result.y := a.z * b.x - a.x * b.z;
  Result.z := a.x * b.y - a.y * b.x;
end;

function VMul(const a, b: TVec2): TVec2;
begin
  Result.x := a.x * b.x; Result.y := a.y * b.y;
end;

function VMul(const a, b: TVec3): TVec3;
begin
  Result.x := a.x * b.x; Result.y := a.y * b.y; Result.z := a.z * b.z;
end;

function VMul(const a, b: TVec4): TVec4;
begin
  Result.x := a.x * b.x; Result.y := a.y * b.y;
  Result.z := a.z * b.z; Result.w := a.w * b.w;
end;

function NormSq(const a: TVec2): Double;
begin
  Result := a.x * a.x + a.y * a.y;
end;

function NormSq(const a: TVec3): Double;
begin
  Result := a.x * a.x + a.y * a.y + a.z * a.z;
end;

function NormSq(const a: TVec4): Double;
begin
  Result := a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w;
end;

function Norm(const a: TVec2): Double;
begin
  Result := Sqrt(NormSq(a));
end;

function Norm(const a: TVec3): Double;
begin
  Result := Sqrt(NormSq(a));
end;

function Norm(const a: TVec4): Double;
begin
  Result := Sqrt(NormSq(a));
end;

function Normalize(const a: TVec2): TVec2;
var n: Double;
begin
  n := Norm(a);
  if n = 0.0 then Result := a
  else Result := a / n;
end;

function Normalize(const a: TVec3): TVec3;
var n: Double;
begin
  n := Norm(a);
  if n = 0.0 then Result := a
  else Result := a / n;
end;

function Normalize(const a: TVec4): TVec4;
var n: Double;
begin
  n := Norm(a);
  if n = 0.0 then Result := a
  else Result := a / n;
end;

function Lerp(const a, b: TVec2; t: Double): TVec2;
begin
  Result := a + (b - a) * t;
end;

function Lerp(const a, b: TVec3; t: Double): TVec3;
begin
  Result := a + (b - a) * t;
end;

function Lerp(const a, b: TVec4; t: Double): TVec4;
begin
  Result := a + (b - a) * t;
end;

{ ---- matrix functions ---- }

function Mat3Identity: TMat3;
var k: Integer;
begin
  for k := 0 to 8 do Result.m[k] := 0.0;
  Result.m[0] := 1.0; Result.m[4] := 1.0; Result.m[8] := 1.0;
end;

function Mat4Identity: TMat4;
var k: Integer;
begin
  for k := 0 to 15 do Result.m[k] := 0.0;
  Result.m[0] := 1.0; Result.m[5] := 1.0;
  Result.m[10] := 1.0; Result.m[15] := 1.0;
end;

function Mat3Scale(sx, sy, sz: Double): TMat3;
begin
  Result := Mat3Identity;
  Result.m[0] := sx; Result.m[4] := sy; Result.m[8] := sz;
end;

function Mat4Scale(sx, sy, sz: Double): TMat4;
begin
  Result := Mat4Identity;
  Result.m[0] := sx; Result.m[5] := sy; Result.m[10] := sz;
end;

function Mat4Translate(tx, ty, tz: Double): TMat4;
begin
  Result := Mat4Identity;
  Result.m[3] := tx; Result.m[7] := ty; Result.m[11] := tz;
end;

function Mat3RotateZ(angle: Double): TMat3;
var c, s: Double;
begin
  c := Cos(angle); s := Sin(angle);
  Result := Mat3Identity;
  Result.m[0] := c; Result.m[1] := -s;
  Result.m[3] := s; Result.m[4] := c;
end;

function Mat4RotateX(angle: Double): TMat4;
var c, s: Double;
begin
  c := Cos(angle); s := Sin(angle);
  Result := Mat4Identity;
  Result.m[5] := c;  Result.m[6] := -s;
  Result.m[9] := s;  Result.m[10] := c;
end;

function Mat4RotateY(angle: Double): TMat4;
var c, s: Double;
begin
  c := Cos(angle); s := Sin(angle);
  Result := Mat4Identity;
  Result.m[0] := c;   Result.m[2] := s;
  Result.m[8] := -s;  Result.m[10] := c;
end;

function Mat4RotateZ(angle: Double): TMat4;
var c, s: Double;
begin
  c := Cos(angle); s := Sin(angle);
  Result := Mat4Identity;
  Result.m[0] := c; Result.m[1] := -s;
  Result.m[4] := s; Result.m[5] := c;
end;

function Transpose(const a: TMat3): TMat3;
var row, col: Integer;
begin
  for row := 0 to 2 do
    for col := 0 to 2 do
      Result.m[col * 3 + row] := a.m[row * 3 + col];
end;

function Transpose(const a: TMat4): TMat4;
var row, col: Integer;
begin
  for row := 0 to 3 do
    for col := 0 to 3 do
      Result.m[col * 4 + row] := a.m[row * 4 + col];
end;

function Det(const a: TMat3): Double;
begin
  Result := a.m[0] * (a.m[4] * a.m[8] - a.m[5] * a.m[7])
          - a.m[1] * (a.m[3] * a.m[8] - a.m[5] * a.m[6])
          + a.m[2] * (a.m[3] * a.m[7] - a.m[4] * a.m[6]);
end;

function Det(const a: TMat4): Double;
{ Laplace expansion along row 0 over 3x3 minors. }
  function Minor(r0, r1, r2, c0, c1, c2: Integer): Double;
  begin
    Result := a.m[r0 * 4 + c0] * (a.m[r1 * 4 + c1] * a.m[r2 * 4 + c2] - a.m[r1 * 4 + c2] * a.m[r2 * 4 + c1])
            - a.m[r0 * 4 + c1] * (a.m[r1 * 4 + c0] * a.m[r2 * 4 + c2] - a.m[r1 * 4 + c2] * a.m[r2 * 4 + c0])
            + a.m[r0 * 4 + c2] * (a.m[r1 * 4 + c0] * a.m[r2 * 4 + c1] - a.m[r1 * 4 + c1] * a.m[r2 * 4 + c0]);
  end;
begin
  Result := a.m[0] * Minor(1, 2, 3, 1, 2, 3)
          - a.m[1] * Minor(1, 2, 3, 0, 2, 3)
          + a.m[2] * Minor(1, 2, 3, 0, 1, 3)
          - a.m[3] * Minor(1, 2, 3, 0, 1, 2);
end;

function MulMV(const a: TMat3; const v: TVec3): TVec3;
begin
  Result.x := a.m[0] * v.x + a.m[1] * v.y + a.m[2] * v.z;
  Result.y := a.m[3] * v.x + a.m[4] * v.y + a.m[5] * v.z;
  Result.z := a.m[6] * v.x + a.m[7] * v.y + a.m[8] * v.z;
end;

function MulMV(const a: TMat4; const v: TVec4): TVec4;
begin
  Result.x := a.m[0] * v.x + a.m[1] * v.y + a.m[2] * v.z + a.m[3] * v.w;
  Result.y := a.m[4] * v.x + a.m[5] * v.y + a.m[6] * v.z + a.m[7] * v.w;
  Result.z := a.m[8] * v.x + a.m[9] * v.y + a.m[10] * v.z + a.m[11] * v.w;
  Result.w := a.m[12] * v.x + a.m[13] * v.y + a.m[14] * v.z + a.m[15] * v.w;
end;

end.
