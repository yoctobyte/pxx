program test_setlength_on_a_shortstring_clamps_at_255;
{ SetLength on a ShortString clamps the count at 255, as fpc does. pxx stored
  the count's low byte instead (1000 read back as 232, 400 as 144), and a fill
  loop over Length(s) then ran past the buffer. Each row fills to Length and
  checks a neighbouring guard. Expected output is fpc 3.2.2's.
  bug-a-setlength-on-a-shortstring-does-not-clamp-at-its-capacity }
{$mode objfpc}
uses SysUtils;
var
  s: ShortString;
  guard: Integer;
  t: string[10];
  n, calls, i: Integer;

function Count: Integer;
begin
  Inc(calls);
  Result := 400;
end;

procedure ByVar(var x: ShortString);
begin
  SetLength(x, n);
  for i := 1 to Length(x) do x[i] := 'v';
  writeln('byvar ', Length(x));
end;

begin
  guard := 12345;
  SetLength(s, 1000);
  for i := 1 to Length(s) do s[i] := 'x';
  writeln('literal ', Length(s), ' ', guard);
  n := 1000;
  SetLength(s, n);
  for i := 1 to Length(s) do s[i] := 'y';
  writeln('variable ', Length(s), ' ', guard);
  calls := 0;
  SetLength(s, Count);
  writeln('once ', Length(s), ' ', calls);
  n := 3000;
  ByVar(s);
  n := 7;
  SetLength(t, n);
  writeln('fits ', Length(t));
  s := StringOfChar('a', 250);
  Insert('0123456789', s, 5);
  writeln('insert ', Length(s), ' ', Copy(s, 1, 8));
  s := StringOfChar('b', 250) + '0123456789';
  writeln('concat ', Length(s), ' ', s[255]);
  t := 'abc';
  t := t + '0123456789';
  writeln('concat10 ', Length(t), ' ', t);
  s := IntToHex(1, 300);
  writeln('inttohex ', Length(s));
  Str(42:20, t);
  writeln('str10 ', Length(t), ' [', t, ']');
  writeln('guard ', guard);
end.
