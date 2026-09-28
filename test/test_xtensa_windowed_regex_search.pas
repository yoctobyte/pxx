program test_xtensa_windowed_regex_search;
uses regex;
var r: TRegex; m: TReMatch; s: AnsiString;
begin
  s := 'id 42-abc x';
  r := ReCompile('(\d+)-(\w+)', 0);
  m := ReSearch(r, s);
  WriteLn(ReGroup(m, s, 1), ' ', ReGroup(m, s, 2));
  WriteLn(ReQuickMatch('a+b', 'aaab', 0));
end.
