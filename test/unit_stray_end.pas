unit unit_stray_end;
{ A routine body one `end` short: the `end` on the line before `end.` belongs
  to nothing. Before 2026-09-04 the implementation pre-scan swallowed it with a
  bare `Next` and the unit compiled clean -- the invisible half of the class,
  because the mirror (one `end` too MANY) does error, just at EOF.
  bug-p-a-stray-end-at-unit-implementation-top-level-is-silently-skipped }
interface
procedure StrayA;
implementation
procedure StrayA;
begin
  WriteLn('a');
end;
end
end.
