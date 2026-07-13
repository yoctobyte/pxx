{ Untyped string constants must be SCOPED.

  The constant table was FLAT: a `const S = 'x';` declared inside one routine stayed
  visible to every routine parsed after it, and the lookup returned the FIRST match — so
  the leaked constant even beat a later routine's OWN constant of the same name. The wrong
  TEXT was substituted, silently.

  FindStrConst is now innermost-wins, like FindSym: the current routine's own constants
  first (newest first, so a redeclaration shadows), then unit-level ones. A constant
  belonging to some OTHER routine is not visible at all.

  Every expected value below is FPC's. }
program test_string_const_scoping_b314;
{$mode objfpc}{$H+}

const
  G = 'outer-G';
  Shared = 'unit-level';

{ each routine's own const must win inside it... }
function A: string;
const
  S = 'A-local';
begin
  A := S;
end;

{ ...and must NOT leak into the next one, which has its own }
function B: string;
const
  S = 'B-local';
begin
  B := S;
end;

{ a routine with no local G sees the UNIT-level G }
function UsesOuter: string;
begin
  UsesOuter := G;
end;

{ a local G shadows the unit-level G inside this routine only }
function ShadowsOuter: string;
const
  G = 'inner-G';
begin
  ShadowsOuter := G;
end;

{ after the shadowing routine, the unit-level G must be back }
function OuterAgain: string;
begin
  OuterAgain := G;
end;

{ concatenation and comparison still work through the scoped lookup }
function Combine: string;
const
  Sep = '/';
begin
  Combine := Shared + Sep + G;
end;

begin
  writeln('A=', A);
  writeln('B=', B);
  writeln('UsesOuter=', UsesOuter);
  writeln('ShadowsOuter=', ShadowsOuter);
  writeln('OuterAgain=', OuterAgain);
  writeln('Combine=', Combine);
end.
