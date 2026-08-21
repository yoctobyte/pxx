program test_not_of_negated_operand;
{$mode objfpc}{$H+}
uses SysUtils;

var n: Integer; i64: Int64; b: Boolean;

begin
  { `not` over a UNARY MINUS is a BITWISE not -- negation is unambiguously
    numeric, so it can never be one of the logically-boolean expressions the
    frontend sometimes tags as integer. These printed TRUE. }
  WriteLn('lit  = ', not -1);
  WriteLn('par  = ', not (-1));
  WriteLn('sp   = ', not (- 1));
  WriteLn('neg2 = ', not (-2));
  n := 5;
  WriteLn('var  = ', not (-n));
  WriteLn('varp = ', not -n);
  i64 := 5;
  WriteLn('i64  = ', not (-i64));

  { the rows that already worked, so a regression the other way shows too }
  WriteLn('p1   = ', not 1);
  WriteLn('p0   = ', not 0);
  WriteLn('pv   = ', not n);
  WriteLn('bin  = ', not (0-1));
  WriteLn('add  = ', not (1+1));

  { a genuine BOOLEAN not must stay logical }
  b := False;
  WriteLn('bool = ', not b);
  WriteLn('cmp  = ', not (n = 5));
end.
