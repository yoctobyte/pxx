{$mode objfpc}
program test_upcase_pos;

{ System intrinsics UpCase (Char) and Pos (substring search, 1-based, 0 if not
  found), lowered to builtin helpers with no `uses`. FPC oracle:
  AZ5 / 3 / 0 / 1 / HI3. }

var
  s, r: string;
  i: Integer;
begin
  writeln(UpCase('a'), UpCase('Z'), UpCase('5'));   { AZ5 }
  writeln(Pos('cd', 'abcde'));                        { 3 }
  writeln(Pos('xy', 'abcde'));                        { 0 }
  writeln(Pos('a', 'abcabc'));                        { 1 }
  s := 'Hi3'; r := '';
  for i := 1 to Length(s) do r := r + UpCase(s[i]);
  writeln(r);                                         { HI3 }
end.
