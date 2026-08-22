program test_source_type_beats_unit_function;
{ A TYPE declared here beats a same-named ROUTINE from a used unit, in front of
  `(` — the position where a type name is a CAST. `type PI = ^Integer` bound
  PI(pp) to math's paramless Pi and failed with "no overload of PI matches
  these arguments", an error about arguments for a construct that has none.
  bug-a-a-source-type-alias-loses-to-a-used-units-function-in-a-cast }
uses Math;
type
  PI  = ^Integer;          { collides with the FUNCTION Pi }
  Fmt = ^AnsiString;       { collides with nothing — the control }
var
  i: Integer; q: PI; pp: Pointer;
  s: AnsiString; sp: Fmt;
  d: Double; ok: Integer;
begin
  ok := 0;
  i := 42; q := @i; pp := q;
  if PI(pp)^ = 42 then Inc(ok);
  s := 'hi'; sp := @s; pp := sp;
  if Fmt(pp)^ = 'hi' then Inc(ok);
  { the ROUTINE is still reachable by its own name — pxx's dialect is lax here
    where FPC's shadowing is total, so this row does NOT have an FPC twin }
  d := Pi;
  if (d > 3.14) and (d < 3.15) then Inc(ok);
  { and the cast still wins in front of `(` after the routine has been used }
  pp := nil;
  if PI(pp) = nil then Inc(ok);
  WriteLn('total ok ', ok, ' / 4');
end.
