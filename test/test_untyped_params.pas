{$mode objfpc}
program test_untyped_params;

{ Untyped var/const parameters (`var x` / `const x`, no type) — the FPC feature
  that lets Move/FillChar-style routines accept any-typed memory by reference.
  The caller passes the address of any lvalue; the callee reaches the bytes via
  @x. Exercises both an untyped `var` (fill target) and an untyped `const`
  (move source) plus a `var` (move dest). FPC oracle: "7 7 7 7 " twice. }

procedure MyFill(var x; n: Integer; v: Byte);
var p: PByte; i: Integer;
begin
  p := PByte(@x);
  for i := 0 to n - 1 do begin p^ := v; Inc(p); end;
end;

procedure MyMove(const src; var dst; n: Integer);
var ps, pd: PByte; i: Integer;
begin
  ps := PByte(@src); pd := PByte(@dst);
  for i := 0 to n - 1 do begin pd^ := ps^; Inc(ps); Inc(pd); end;
end;

var
  a, b: array[0..3] of Byte;
  i: Integer;
begin
  MyFill(a, 4, 7);                          { untyped var, any-typed lvalue }
  for i := 0 to 3 do Write(a[i], ' ');
  WriteLn;                                  { 7 7 7 7 }
  MyMove(a, b, 4);                          { untyped const + untyped var }
  for i := 0 to 3 do Write(b[i], ' ');
  WriteLn;                                  { 7 7 7 7 }
end.
