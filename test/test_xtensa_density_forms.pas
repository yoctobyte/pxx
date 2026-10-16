program test_xtensa_density_forms;
{ On xtensa the six commonest instructions take their 2-byte density form when
  the operands fit (movi.n -32..95, addi.n -1/1..15, l32i.n/s32i.n offsets
  0..60, mov.n, add.n), and a windowed procedure reserves only the
  outgoing-argument area its widest call needs, so most spill slots start at
  sp+0 and sp never moves. Values on both sides of every narrow boundary;
  locals past offset 60; deep expression spills; calls of 7, 8, 22, 23 and 30
  words, direct, indirect and virtual; an atomic retry loop and nested
  exceptions (both hand-counted sequences that must stay 3-byte); and an asm
  block that branches over narrowed instructions to a label. Prints the same on x64. }
{$mode objfpc}
uses SysUtils;

type
  TSeven = function(a, b, c, d, e, f, g: LongInt): LongInt;

  TBase = class
    function Many(a, b, c, d, e, f, g, h: LongInt): LongInt; virtual;
  end;

  TDerived = class(TBase)
    function Many(a, b, c, d, e, f, g, h: LongInt): LongInt; override;
  end;

function TBase.Many(a, b, c, d, e, f, g, h: LongInt): LongInt;
begin
  Result := a + b + c + d + e + f + g + h;
end;

function TDerived.Many(a, b, c, d, e, f, g, h: LongInt): LongInt;
begin
  Result := inherited Many(a, b, c, d, e, f, g, h) * 2 + h;
end;

function Id(x: LongInt): LongInt;
begin
  Result := x;
end;

function Seven(a, b, c, d, e, f, g: LongInt): LongInt;
begin
  Result := a - b + c - d + e - f + g * 7;
end;

function EightWords(a: Int64; b, c, d, e, f, g: LongInt): Int64;
begin
  Result := a * 3 + b + c + d + e + f + g;
end;

function TwentyTwo(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11,
                   a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22: LongInt): LongInt;
begin
  Result := a1 + a22 * 2 + a11 * 3 + a7 - a6 + a12 * a13;
end;

function TwentyThree(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11,
                     a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23: LongInt): LongInt;
begin
  Result := a1 + a23 * 5 + a22 * 2 - a7 + a16;
end;

function Thirty(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, a14, a15: Int64): Int64;
begin
  Result := a1 + a15 * 1000000007 + a8 - a7 + a14;
end;

function Consts(k: LongInt): LongInt;
var v: array[0..11] of LongInt;
    i: LongInt;
begin
  v[0] := -33; v[1] := -32; v[2] := -1; v[3] := 0; v[4] := 95; v[5] := 96;
  v[6] := 2047; v[7] := -2048; v[8] := 15; v[9] := 16; v[10] := 1; v[11] := 64;
  Result := 0;
  for i := 0 to 11 do
    Result := Result * 3 + v[i] * k;
end;

function AddImm(x: LongInt): LongInt;
begin
  Result := (x - 2) + (x - 1) + (x + 0) + (x + 1) + (x + 15) + (x + 16)
            + (x - 128) + (x + 127) + (x + 200);
end;

function ManyLocals(k: LongInt): LongInt;
var l0, l1, l2, l3, l4, l5, l6, l7, l8, l9, l10, l11, l12, l13, l14, l15,
    l16, l17, l18, l19, l20, l21, l22, l23, l24: LongInt;
begin
  l0 := k; l1 := l0 + 1; l2 := l1 + 2; l3 := l2 + 3; l4 := l3 + 4;
  l5 := l4 + 5; l6 := l5 + 6; l7 := l6 + 7; l8 := l7 + 8; l9 := l8 + 9;
  l10 := l9 + 10; l11 := l10 + 11; l12 := l11 + 12; l13 := l12 + 13;
  l14 := l13 + 14; l15 := l14 + 15; l16 := l15 + 16; l17 := l16 + 17;
  l18 := l17 + 18; l19 := l18 + 19; l20 := l19 + 20; l21 := l20 + 21;
  l22 := l21 + 22; l23 := l22 + 23; l24 := l23 + 24;
  Result := l0 + l5 + l10 + l15 + l20 + l24 + Id(l3) * Id(l17) - Id(l23);
end;

function Spill(a, b, c, d: LongInt): LongInt;
begin
  { nested calls keep partial results on the expression stack }
  Result := Id(a + Id(b * Id(c - Id(d + Id(a * 2))))) * Id(Id(b) - Id(Id(c) + Id(d)))
            + Seven(Id(a), Id(b), Id(c), Id(d), Id(a + b), Id(c + d), Id(a - d));
end;

function AtomicSum(n: LongInt): LongInt;
var counter, i, old: LongInt;
begin
  counter := 0;
  for i := 1 to n do
    old := __pxxatomic_add(@counter, i);
  Result := counter * 1000 + (old and 1023);
end;

function Guarded(k: LongInt): LongInt;
var s: string;
begin
  Result := 0;
  try
    try
      s := IntToStr(Seven(k, 1, 2, 3, 4, 5, 6));
      if k > 2 then
        raise Exception.Create('inner ' + s);
      Result := k;
    finally
      Result := Result + 100;
    end;
  except
    on e: Exception do
      Result := -Length(e.Message) - TwentyTwo(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
                                               12, 13, 14, 15, 16, 17, 18, 19, 20, 21, k);
  end;
end;

function AsmSkip: LongInt;
var r: LongInt;
begin
  r := 0;
{$ifdef CPUXTENSA}
  { asm branches go to labels, resolved by position, so narrowed
    instructions between the branch and its label are fine }
  asm
    movi a10, 1
    movi a11, 1
    beq a10, a11, skip
    movi a10, 2
    mov a11, a10
    addi a10, a10, 3
  skip:
    add a10, a10, a11
    s32i a10, r
  end;
{$else}
  r := 2;
{$endif}
  Result := r;
end;

var
  fn: TSeven;
  o: TBase;
  i: LongInt;
begin
  writeln('consts ', Consts(1), ' ', Consts(-3));
  writeln('addimm ', AddImm(0), ' ', AddImm(1000));
  writeln('locals ', ManyLocals(1), ' ', ManyLocals(-50));
  writeln('spill ', Spill(1, 2, 3, 4), ' ', Spill(-7, 11, 13, -17));
  writeln('seven ', Seven(1, 2, 3, 4, 5, 6, 7));
  writeln('eight ', EightWords(Int64(1) shl 40, 1, 2, 3, 4, 5, 6));
  writeln('22 ', TwentyTwo(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22));
  writeln('23 ', TwentyThree(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23));
  writeln('30 ', Thirty(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15));
  fn := @Seven;
  writeln('indirect ', fn(7, 6, 5, 4, 3, 2, 1), ' ', fn(Id(1), Id(2), 3, 4, 5, 6, Id(7)));
  o := TDerived.Create;
  writeln('virtual ', o.Many(1, 2, 3, 4, 5, 6, 7, 8));
  o.Free;
  writeln('atomic ', AtomicSum(10), ' ', AtomicSum(100));
  for i := 1 to 4 do write(Guarded(i), ' ');
  writeln;
  writeln('asm ', AsmSkip);
end.
