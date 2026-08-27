{ The variadic `Concat` intrinsic must survive a unit that declares a `Concat`
  of its own.

  `lib/rtl/sysutils` declares a two-argument one, and the intrinsic's guard was
  `procIdx < 0` — ANY Concat in scope withdrew it outright. So this program
  compiled without line 2 and failed with it:

    no overload of Concat matches these arguments
      candidates: Concat(AnsiString, AnsiString)

  The dynamic-array form went the same way and for a sharper reason: sysutils'
  Concat has the right ARITY for two arrays and entirely the wrong types, so no
  arity rule could have saved it either.

  Shadowing a builtin with a routine of the same name is right; withdrawing it
  for calls that routine cannot accept is not. The intrinsic is now picked up at
  the point where matching has been DECIDED rather than guessed — the same pair
  of arms `Copy` already has, whose own comment says the two must stay in step.

  Every row below is `fpc -O1 -Mobjfpc` 3.2.2's, and FPC needs no shadow rule
  here at all: its own sysutils does not declare Concat. }
program test_concat_survives_uses_sysutils;
uses sysutils;
var
  a, b, c: array of Integer;
  i: Integer;
  s: string;
begin
  writeln(Concat('a', 'b', 'c'));       { variadic — the reported break }
  writeln(Concat('a', 'b'));            { two args — sysutils' own, unshadowed }
  writeln(Concat('solo'));              { one arg — the identity }
  s := 'x';
  writeln(Concat(s, 'y', 'z'));         { a variable first, not a literal }
  writeln(Concat('n=', IntToStr(42)));  { and a real sysutils call beside it }

  SetLength(a, 2); a[0] := 1; a[1] := 2;
  SetLength(b, 2); b[0] := 3; b[1] := 4;
  c := Concat(a, b);                    { right arity for sysutils, wrong types }
  for i := 0 to High(c) do write(c[i], ' ');
  writeln;
  c := Concat(a, b, a);
  for i := 0 to High(c) do write(c[i], ' ');
  writeln;
end.
