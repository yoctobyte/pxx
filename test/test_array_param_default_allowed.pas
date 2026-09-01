{$mode objfpc}
program test_array_param_default_allowed;

{ The positive control for test_array_param_default_refused: the shapes next to
  the refused one that must KEEP compiling. A named dynamic-array type param is
  a handle, so `nil` is a real default and FPC accepts it; an open-array param
  alongside a defaulted scalar is the mixed shape a too-broad guard breaks.
  Both were broken by the first version of that guard, which asked `isArr` --
  true for open, named-fixed and named-dynamic array params alike. }

type
  TArr = array of Integer;

procedure WithDyn(a: TArr = nil);
begin
  writeln('dyn len=', Length(a));
end;

procedure Mixed(const a: array of string; b: Integer = 7);
begin
  writeln('mixed high=', High(a), ' b=', b);
end;

var
  s: array[0..1] of string;
  v: TArr;
begin
  s[0] := 'p'; s[1] := 'q';
  WithDyn;
  SetLength(v, 3);
  WithDyn(v);
  Mixed(s);
  Mixed(s, 9);
end.
