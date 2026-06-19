program test_cross_frozen_strlen_deref;

{ Cross-target oracle for Length() of a frozen `string` reached through a
  pointer deref or a pointer field. `ps^` / `r.np^` lower to a bare pointer
  load whose value IS the frozen buffer address, so the length prefix sits at
  [buf+0] (not at the [handle-8] dynamic-array slot). Previously the cross
  backends fell to the handle path and returned 0; now they read [buf+0] like
  x86-64. Output is identical on every target. }

type
  PStr = ^string;
  TRec = record np: PStr; end;

var
  s, t: string;
  ps: PStr;
  r: TRec;
begin
  s := 'TRoot';
  t := 'hi';
  ps := @s;
  r.np := @s;

  writeln(Length(s));        { 5  — baseline direct }
  writeln(Length(ps^));      { 5  — local pointer deref }
  writeln(Length(r.np^));    { 5  — pointer field deref }

  ps := @t;
  r.np := @t;
  writeln(Length(ps^));      { 2  — re-pointed local }
  writeln(Length(r.np^));    { 2  — re-pointed field }
end.
