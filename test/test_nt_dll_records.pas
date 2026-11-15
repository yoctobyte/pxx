program test_nt_dll_records;
{ Records by value to and from a DLL under --os=nt: the Microsoft x64 rule
  (1/2/4/8 bytes as an integer, other sizes through a pointer to a copy; a
  1/2/4/8-byte result in rax, a larger one through a hidden first argument).
  The callee is test/win_recdll.c, built into win_recdll.dll by test-windows.
  feature-port-windows-pe }
type
  P8 = record x, y: LongInt; end;
  P2 = record a: SmallInt; end;
  P12 = record a, b, c: LongInt; end;
  PD = record d: Double; end;
  PF = record a, b: Single; end;
function ret8(a, b: LongInt): P8; cdecl; external 'win_recdll.dll';
function ret2(a: SmallInt): P2; cdecl; external 'win_recdll.dll';
function ret12(a: LongInt; s: Double; b: LongInt): P12; cdecl; external 'win_recdll.dll';
function take8(k: LongInt; p: P8): Int64; cdecl; external 'win_recdll.dll';
function take2(p: P2; k: LongInt): LongInt; cdecl; external 'win_recdll.dll';
function take12(p: P12; k: LongInt; q: P12): Int64; cdecl; external 'win_recdll.dll';
function takeD(p: PD; s: Double): Double; cdecl; external 'win_recdll.dll';
function takeF(p: PF): Double; cdecl; external 'win_recdll.dll';
function take6(a, b, c, d: LongInt; e: P8; f: P12): Int64; cdecl; external 'win_recdll.dll';
var r: P8; r2: P2; r12: P12; p8v: P8; p2v: P2; a, q: P12; pd1: PD; pf1: PF;
begin
  p8v.x := 3; p8v.y := 4;
  WriteLn('take8 ', take8(7, p8v));                 { 7034 }
  p2v.a := -5;
  WriteLn('take2 ', take2(p2v, 12));                { 7 }
  a.a := 1; a.b := 2; a.c := 3; q.a := 0; q.b := 0; q.c := 5;
  WriteLn('take12 ', take12(a, 4, q), ' a.a after ', a.a);   { 99+20+300+4000+50000 = 54419, 1 }
  pd1.d := 2.5;
  WriteLn('takeD ', takeD(pd1, 4.0):0:2);          { 10.00 }
  pf1.a := 1.5; pf1.b := 2.25;
  WriteLn('takeF ', takeF(pf1):0:2);               { 3.75 }
  WriteLn('take6 ', take6(1, 2, 3, 4, p8v, a));    { 10+3+40+300 = 353 }
  r := ret8(5, 6);
  WriteLn('ret8 ', r.x, ' ', r.y);
  r2 := ret2(-7);
  WriteLn('ret2 ', r2.a);
  r12 := ret12(1, 2.5, 9);
  WriteLn('ret12 ', r12.a, ' ', r12.b, ' ', r12.c);
  WriteLn('inline ', ret8(1, 2).y + ret12(3, 1.0, 4).c);
end.
