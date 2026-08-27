program test_frozen_string_length_byte;
{ `s[0]` is the classic shortstring LENGTH BYTE, not a character — FPC's own
  compiler sources build strings with it (cutils.pas:1429 is
  `inc(minilzw_encode[0])`). pxx addresses a frozen string as base + (i - lo)
  with lo = -7, so index 1 lands on data[0] at base+8 and index 0 landed on
  base+7: the TOP byte of the 8-byte length word. `ord(s[0])` answered 0 where
  FPC says 2, and `s[0] := #1` wrote $0100000000000002 into the length.
  Silently wrong in both directions, no diagnostic.
  bug-p-index-0-of-a-frozen-string-is-not-the-length-byte }
{$mode objfpc}

type
  TStr8 = string[8];

procedure Grow(var s: shortstring; c: Char);
begin
  inc(s[0]);
  s[Length(s)] := c;
end;

var
  s: shortstring;
  f: TStr8;
  r: record a: shortstring; end;
  i: Integer;
begin
  s := 'ab';
  writeln('a ', ord(s[0]), '|', Length(s));
  { grow through the length byte, FPC's own idiom }
  inc(s[0]);
  s[3] := 'c';
  writeln('b ', s, '|', Length(s));
  { truncate through it }
  s[0] := #1;
  writeln('c ', s, '|', Length(s));
  { …and back to empty, then rebuilt one char at a time through a var param }
  s[0] := #0;
  writeln('d ', '<', s, '>|', Length(s));
  Grow(s, 'x'); Grow(s, 'y'); Grow(s, 'z');
  writeln('e ', s, '|', Length(s));
  { the sized string[N] spelling takes the same path }
  f := 'pqrs';
  writeln('f ', ord(f[0]));
  f[0] := #2;
  writeln('g ', f, '|', Length(f));
  { a frozen string in a RECORD field }
  r.a := 'hello';
  writeln('h ', ord(r.a[0]));
  r.a[0] := #3;
  writeln('i ', r.a);
  { a RUNTIME index still walks the characters, unchanged }
  s := 'abc';
  f := '';
  for i := 1 to Length(s) do f := f + s[i];
  writeln('j ', f);
  writeln('OK');
end.
