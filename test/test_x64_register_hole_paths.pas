{ Register-hole codegen paths, raw-asm batch 23 (2026-11-11). These moved from
  computed opcode bytes (`EmitB($C0 or (r - 8))`) to %r64/%xmm register holes:
  - the unsigned qword -> double fix-up (EmitCvtSi2SdOrU64);
  - -O3 float residents in xmm8+ (save/restore, movaps to and from the
    resident, float-tree arithmetic);
  - r12..r15 integer residents (W2 in-place ALU, narrow write-back and
    re-extend, cmp/imul against a resident).
  The output must be the same at every level. }
program test_x64_register_hole_paths;
{$mode objfpc}
var
  q: QWord; d: Double; i, k: Integer; acc, a, b: Int64; f, g, h: Double;

function FloatMix(x, y: Double; n: Integer): Double;
var p, r: Double; j: Integer;
begin
  p := x; r := y;
  for j := 1 to n do
  begin
    p := p * 1.5 + r;
    r := r - p / 7.0;
  end;
  Result := p + r;
end;

function IntMix(n: Int64): Int64;
var x, y, z: Int64; j: Integer;
begin
  x := n; y := 3; z := 0;
  for j := 1 to 20 do
  begin
    x := x + y; y := y xor x; z := z or (x and 255); x := x - 7;
    if x > 100000 then x := x and $FFFF;
    z := z + j * 12345;
  end;
  Result := x + y + z;
end;

{ one narrow variable per function, so it is the one that gets a register:
  the W2 in-place add, the narrow write-back and the re-extend are on it }
function NarrowS8(n: Integer): Int64;
var v: ShortInt; j: Integer;
begin v := 0; for j := 1 to n do v := v + 100; Result := v; end;
function NarrowU8(n: Integer): Int64;
var v: Byte; j: Integer;
begin v := 0; for j := 1 to n do v := v + 91; Result := v; end;
function NarrowS16(n: Integer): Int64;
var v: SmallInt; j: Integer;
begin v := 0; for j := 1 to n do v := v + 30000; Result := v; end;
function NarrowU16(n: Integer): Int64;
var v: Word; j: Integer;
begin v := 0; for j := 1 to n do v := v + 54321; Result := v; end;
function NarrowS32(n: Integer): Int64;
var v: LongInt; j: Integer;
begin v := 0; for j := 1 to n do v := v + 1500000000; Result := v; end;
function NarrowU32(n: Integer): Int64;
var v: LongWord; j: Integer;
begin v := 0; for j := 1 to n do v := v + 3123456789; Result := v; end;

begin
  q := QWord($FFFFFFFFFFFFF801); d := q; WriteLn(d:0:1);
  q := QWord(1) shl 63; d := q; WriteLn(d:0:1);
  q := 12345; d := q; WriteLn(d:0:1);
  for i := 0 to 3 do WriteLn(FloatMix(1.25 + i, 2.5, 10 + i):0:6);
  for i := 0 to 3 do WriteLn(IntMix(i * 1000));
  for i := 1 to 4 do
    WriteLn(NarrowS8(i * 7), ' ', NarrowU8(i * 7), ' ', NarrowS16(i * 7), ' ',
            NarrowU16(i * 7), ' ', NarrowS32(i * 7), ' ', NarrowU32(i * 7));
  acc := 0;
  for k := 1 to 1000 do begin a := k * 7; b := k xor 99; if a > b then acc := acc + a * 3 else acc := acc - b; end;
  WriteLn(acc);
  f := 0.5; g := 1.0; h := 0;
  for k := 1 to 50 do begin h := h + f * g; f := f + 0.25; g := g - 0.01; end;
  WriteLn(h:0:6);
end.
