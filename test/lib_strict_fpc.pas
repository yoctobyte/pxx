program lib_strict_fpc;
{ --strict-fpc umbrella smoke (Track P). The KEY property: the bundle
  (case/operator/visibility/require-forward — NOT StrictOverload) coexists with
  the lax RTL, so an ordinary RTL-using program still compiles under --strict-fpc.
  Compile this WITH --strict-fpc; if StrictOverload had been bundled it would fail
  on the RTL's undirectived overloads. See feature-strict-fpc-umbrella. }
uses sysutils;

{ require-forward is ON under --strict-fpc: this routine is defined ABOVE its use,
  so it is fine (a use-before-definition would error — that is the point). }
function Doubled(n: Integer): Integer;
begin
  Doubled := n * 2;
end;

begin
  writeln(IntToStr(Doubled(21)), ' ', UpperCase('ok'));
end.
