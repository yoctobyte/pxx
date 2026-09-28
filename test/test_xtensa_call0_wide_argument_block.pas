program test_xtensa_call0_wide_argument_block;

{$mode objfpc}

{ A call whose argument block is 128 bytes or more, on every call form.

  Call0 xtensa pops the block after the call with `addi sp, sp, nArgs*4`, and
  addi encodes -128..127. Nothing checked that before emitting, so a 32-word
  call (exactly 128 bytes) stopped the build with "addi immediate
  displacement 128 is outside the encodable range". That call is pyeval's
  32-argument closure bridge, which is appended to every Nil Python program, so
  Nil Python could not build for Call0 at all.

  The shapes: 32 Integers is exactly 128 bytes, the first value past the range.
  20 Int64s is 160 bytes, past it on any count. A virtual method with 31
  Integers plus Self is 128 bytes. 32 is the parameter cap
  (bug-a-max-proc-params-is-coupled-to-a-hardcoded-array-bound-by-a-comment),
  which is why the wide block is made of Int64s rather than more parameters.

  Values alone are not the assertion. A pop that is wrong by one step leaves
  sp off by that amount, so the calls run in a loop, and locals are read
  after it: a drifting sp shows up as a wrong total or a corrupted guard long
  before it crashes.
  bug-a-nil-python-does-not-build-for-xtensa-call0 }

type
  TW32 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31: Integer): Integer;
  TL20 = function(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19: Int64): Int64;
  TObj = class
    k: Integer;
    function M31(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30: Integer): Integer; virtual;
  end;

function W32(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30, a31: Integer): Integer;
begin
  W32 := a0*1 + a1*2 + a2*3 + a3*4 + a4*5 + a5*6 + a6*7 + a7*8 + a8*9 + a9*10 + a10*11 + a11*12 + a12*13 + a13*14 + a14*15 + a15*16 + a16*17 + a17*18 + a18*19 + a19*20 + a20*21 + a21*22 + a22*23 + a23*24 + a24*25 + a25*26 + a26*27 + a27*28 + a28*29 + a29*30 + a30*31 + a31*32;
end;

function L20(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19: Int64): Int64;
begin
  L20 := a0*1 + a1*2 + a2*3 + a3*4 + a4*5 + a5*6 + a6*7 + a7*8 + a8*9 + a9*10 + a10*11 + a11*12 + a12*13 + a13*14 + a14*15 + a15*16 + a16*17 + a17*18 + a18*19 + a19*20;
end;

function TObj.M31(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24, a25, a26, a27, a28, a29, a30: Integer): Integer;
begin
  M31 := k + a0*1 + a1*2 + a2*3 + a3*4 + a4*5 + a5*6 + a6*7 + a7*8 + a8*9 + a9*10 + a10*11 + a11*12 + a12*13 + a13*14 + a14*15 + a15*16 + a16*17 + a17*18 + a18*19 + a19*20 + a20*21 + a21*22 + a22*23 + a23*24 + a24*25 + a25*26 + a26*27 + a27*28 + a28*29 + a29*30 + a30*31;
end;

function Run: Int64;
var
  guardA, i: Integer;
  total: Int64;
  f32: TW32;
  f20: TL20;
  o: TObj;
  guardB: Integer;
begin
  guardA := 12345;
  guardB := 67890;
  total := 0;
  f32 := @W32;
  f20 := @L20;
  o := TObj.Create;
  o.k := 7;
  for i := 1 to 200 do
  begin
    total := total + W32(i+0, i+1, i+2, i+3, i+4, i+5, i+6, i+7, i+8, i+9, i+10, i+11, i+12, i+13, i+14, i+15, i+16, i+17, i+18, i+19, i+20, i+21, i+22, i+23, i+24, i+25, i+26, i+27, i+28, i+29, i+30, i+31);
    total := total + L20(i+0, i+1, i+2, i+3, i+4, i+5, i+6, i+7, i+8, i+9, i+10, i+11, i+12, i+13, i+14, i+15, i+16, i+17, i+18, i+19);
    total := total + f32(i+0, i+1, i+2, i+3, i+4, i+5, i+6, i+7, i+8, i+9, i+10, i+11, i+12, i+13, i+14, i+15, i+16, i+17, i+18, i+19, i+20, i+21, i+22, i+23, i+24, i+25, i+26, i+27, i+28, i+29, i+30, i+31);
    total := total + f20(i+0, i+1, i+2, i+3, i+4, i+5, i+6, i+7, i+8, i+9, i+10, i+11, i+12, i+13, i+14, i+15, i+16, i+17, i+18, i+19);
    total := total + o.M31(i+0, i+1, i+2, i+3, i+4, i+5, i+6, i+7, i+8, i+9, i+10, i+11, i+12, i+13, i+14, i+15, i+16, i+17, i+18, i+19, i+20, i+21, i+22, i+23, i+24, i+25, i+26, i+27, i+28, i+29, i+30);
  end;
  WriteLn('direct32 ', W32(1+0, 1+1, 1+2, 1+3, 1+4, 1+5, 1+6, 1+7, 1+8, 1+9, 1+10, 1+11, 1+12, 1+13, 1+14, 1+15, 1+16, 1+17, 1+18, 1+19, 1+20, 1+21, 1+22, 1+23, 1+24, 1+25, 1+26, 1+27, 1+28, 1+29, 1+30, 1+31));
  WriteLn('direct20x64 ', L20(1+0, 1+1, 1+2, 1+3, 1+4, 1+5, 1+6, 1+7, 1+8, 1+9, 1+10, 1+11, 1+12, 1+13, 1+14, 1+15, 1+16, 1+17, 1+18, 1+19));
  WriteLn('procvar32 ', f32(2+0, 2+1, 2+2, 2+3, 2+4, 2+5, 2+6, 2+7, 2+8, 2+9, 2+10, 2+11, 2+12, 2+13, 2+14, 2+15, 2+16, 2+17, 2+18, 2+19, 2+20, 2+21, 2+22, 2+23, 2+24, 2+25, 2+26, 2+27, 2+28, 2+29, 2+30, 2+31));
  WriteLn('procvar20x64 ', f20(2+0, 2+1, 2+2, 2+3, 2+4, 2+5, 2+6, 2+7, 2+8, 2+9, 2+10, 2+11, 2+12, 2+13, 2+14, 2+15, 2+16, 2+17, 2+18, 2+19));
  WriteLn('virtual31 ', o.M31(3+0, 3+1, 3+2, 3+3, 3+4, 3+5, 3+6, 3+7, 3+8, 3+9, 3+10, 3+11, 3+12, 3+13, 3+14, 3+15, 3+16, 3+17, 3+18, 3+19, 3+20, 3+21, 3+22, 3+23, 3+24, 3+25, 3+26, 3+27, 3+28, 3+29, 3+30));
  WriteLn('guards ', guardA, ' ', guardB);
  o.Free;
  Run := total;
end;

var t: Int64;
begin
  t := Run;
  WriteLn('total ', t);
end.
