program test_string_sized;
{ Frozen fixed-length string: `string[N]` -> tyFixedString (word length prefix,
  capacity N). Exercises assign, writeln, Length, indexing, and that adjacent
  sized-string slots do NOT clobber each other (the size/offset bug class). }
var
  a: string[16];
  b: string[16];
  c: string[64];
  i: Integer;
begin
  a := 'Apple';
  b := 'Banana';
  c := 'Cherry-and-then-some';
  writeln(a);
  writeln(b);
  writeln(c);
  writeln(Length(a));
  writeln(Length(b));
  writeln(Length(c));
  { adjacency: a and b must be independent }
  if a = 'Apple' then writeln('a-ok') else writeln('a-BAD');
  if b = 'Banana' then writeln('b-ok') else writeln('b-BAD');
  { index }
  for i := 1 to Length(a) do
    Write(a[i]);
  writeln;
end.
