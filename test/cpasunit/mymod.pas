{ A Pascal unit reached from C through `#include "cpasunit/mymod.pas"`, which
  declares its routines under mangled C identifiers (`mymod_pas_Twice`).
  test/cpasunit2/mymod.pas is a SECOND unit with the same name, there to prove
  the collision is refused rather than silently resolving to whichever came
  first. }
unit mymod;
interface
function Twice(x: Integer): Integer;
function Max(a: Integer; b: Integer): Integer; overload;
function Max(a: Double; b: Double): Double; overload;
implementation
function Twice(x: Integer): Integer;
begin
  Twice := x * 2;
end;
function Max(a: Integer; b: Integer): Integer; overload;
begin
  if a > b then Max := a else Max := b;
end;
function Max(a: Double; b: Double): Double; overload;
begin
  if a > b then Max := a else Max := b;
end;
end.
