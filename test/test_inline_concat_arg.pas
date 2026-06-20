program test_inline_concat_arg;
{ Regression for bug-stack-corruption-inline-string-concat: a frozen-string
  concatenation passed inline as a call/method argument must be spilled to a
  stable temp and passed by address, not leave its stack buffer punching a hole
  between the argument pushes of a multi-arg call. }
type
  TF = class
    procedure Show(const s: string);
  end;
procedure TF.Show(const s: string);
begin
  writeln('[', s, '] len=', Length(s));
end;
procedure Plain(const s: string);
begin
  writeln('[', s, '] len=', Length(s));
end;
var f: TF;
begin
  Plain('aa' + 'bb');                 { [aabb] len=4 }
  f := TF.Create;
  f.Show('Line 1' + #10 + 'Line 2');  { [Line 1\nLine 2] len=13 }
  f.Show('x' + 'y' + 'z');            { [xyz] len=3 }
end.
