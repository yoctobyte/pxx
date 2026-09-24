{ The other side of test_var_param_refuses_a_narrower_variable: every shape
  here must still COMPILE AND RUN. Exact types, `out`, a field, an element,
  an explicit lvalue cast (the programmer saying so), untyped `var x`
  (Move/FillChar style, recorded as Pointer internally), an enum, and a
  same-width sign mismatch, which fpc refuses but which cannot corrupt, so
  pxx keeps accepting it. Last, the OVERLOAD shape: with an Int64 and a
  LongInt `var a` row declared Int64-FIRST, `T(i, a)` must bind the LongInt
  row even though `i` converts -- a converting argument used to let
  declaration order pick the wider row, which wrote past `a`. }
program test_var_param_width_rule_accepts_exact_and_cast;
{$mode objfpc}
type
  TR = record w: Word; q: Int64; end;
  TE = (e1, e2, e3);
procedure P(var x: Int64); begin x := x + 1; end;
procedure O(out x: Int64); begin x := 40; end;
procedure U(var x); begin PByte(@x)^ := 7; end;
procedure PE(var x: TE); begin x := e3; end;
procedure PW(var x: LongWord); begin x := x + 2; end;
procedure T(c: Int64; var a: Int64); overload; begin a := -1; end;
procedure T(c: Int64; var a: LongInt); overload; begin a := c * 2; end;
var q: Int64; r: TR; arr: array[0..1] of Int64; a: LongInt; b: Byte; e: TE;
    guard: LongInt; i: Integer; la: LongInt;
begin
  guard := 12345;
  O(q); P(q);
  r.q := 1; P(r.q);
  arr[1] := 5; P(arr[1]);
  U(b);
  e := e1; PE(e);
  a := 3; PW(a);
  writeln(q, ' ', r.q, ' ', arr[1], ' ', b, ' ', Ord(e), ' ', a, ' ', guard);
  i := 21; T(i, la);
  writeln(la, ' ', guard);
end.
