{$mode objfpc}
program test_static_array_length;

{ Length/High of a whole static array fold to compile-time constants
  (bug-static-array-length-direct). The runtime length path reads a [data-8]
  header that only dyn arrays / open-array params have; a bare static array has
  none, so these were returning 0 / -1. FPC oracle: 3 / 2 / 64 / 60. }

{ Multi-dim (>=2) static Length/High/Low used directly fold to the FIRST
  dimension (FPC: Length(m)=dim0 count, High(m)=dim0 upper, Low(m)=dim0 lower).
  Previously took the broken runtime path -> 0 / -1 / 0. Non-zero-based dim0
  (g) exercises the lower-bound arithmetic. FPC oracle: 3 / 2 / 0 / 5 / 9 / 5. }
var
  f: array[0..2] of Integer;
  b: array[0..63] of Byte;
  m: array[0..2, 0..4] of Integer;
  g: array[5..9, 1..3] of Integer;
  i, s: Integer;
begin
  WriteLn(Length(f));          { 3 }
  WriteLn(High(f));            { 2 }
  WriteLn(Length(b));          { 64 }
  f[0] := 10; f[1] := 20; f[2] := 30;
  s := 0;
  for i := 0 to High(f) do s := s + f[i];
  WriteLn(s);                  { 60 }
  WriteLn(Length(m));          { 3 }
  WriteLn(High(m));            { 2 }
  WriteLn(Low(m));             { 0 }
  WriteLn(Length(g));          { 5 }
  WriteLn(High(g));            { 9 }
  WriteLn(Low(g));             { 5 }
end.
