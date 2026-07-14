program test_not_ord_bitwise;
{ `not ord(x)` is a BITWISE complement at the operand's width (FPC parity),
  not a boolean bit-flip. ord(char/boolean) complements as a byte (158/254),
  a 4-byte enum as an integer (-2), and the via-a-variable control stays -2.
  bug-pascal-not-of-ord-uses-boolean-negation. }
{$mode objfpc}
{$Q-}{$R-}
type TE = (e0, e1, e2);
var e: TE; i: longint; c: char; b: boolean; by: byte;
begin
  e := e1; i := 1; c := 'a'; b := true; by := 1;
  writeln(longint(not i));         { -2 }
  writeln(longint(not ord(e)));    { -2 }
  writeln(longint(not ord(c)));    { 158 }
  writeln(longint(not ord(b)));    { 254 }
  writeln(longint(not ord(by)));   { 254: subword integer keeps its width }
  writeln(longint(not by));        { 254: plain byte var complements as byte }
  i := ord(e);
  writeln(longint(not i));         { -2 }
end.
