program test_ctor_wide_args_cross;
{ Int64, Double and QWord constructor arguments, direct and through an
  inherited call, beside 32-bit and managed ones. A 2026-09 audit found an
  xtensa call path that counted every argument as ONE word and could not tell
  read-only whether a wide constructor argument reached it; measured
  2026-11-19, all five cross targets match x86-64. This row keeps it that way.
  bug-a-target-enumerations-in-comments-are-stale-and-one-of-them-hid-a-live-bug }
{$mode objfpc}{$H+}
type
  TP = class
    a: LongInt; b: Int64; c: Double; d: LongInt; e: QWord; s: AnsiString;
    constructor Create(xa: LongInt; xb: Int64; xc: Double; xd: LongInt);
    constructor Mk(xb: Int64; xs: AnsiString; xe: QWord);
  end;
  TQ = class(TP)
    constructor Create(xa: LongInt; xb: Int64; xc: Double; xd: LongInt);
  end;
constructor TP.Create(xa: LongInt; xb: Int64; xc: Double; xd: LongInt);
begin a := xa; b := xb; c := xc; d := xd; end;
constructor TP.Mk(xb: Int64; xs: AnsiString; xe: QWord);
begin b := xb; s := xs; e := xe; end;
constructor TQ.Create(xa: LongInt; xb: Int64; xc: Double; xd: LongInt);
begin inherited Create(xa + 1, xb + 1, xc + 1, xd + 1); end;
var p: TP; x: Int64;
begin
  x := 1234567890123;
  p := TP.Create(7, x, 2.5, 9);
  WriteLn(p.a, ' ', p.b, ' ', p.c:0:2, ' ', p.d);
  p := TP.Mk(-x, 'hi', QWord(1) shl 40);
  WriteLn(p.b, ' ', p.s, ' ', p.e);
  p := TQ.Create(7, x, 2.5, 9);
  WriteLn(p.a, ' ', p.b, ' ', p.c:0:2, ' ', p.d);
end.
