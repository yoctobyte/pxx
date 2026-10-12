program test_esp_idf_str_append_grow;
{ IN-PLACE STRING APPEND READS THE BLOCK'S REAL CAPACITY on the ESP-IDF heap.
  rv32-f (2026-10-13) removed pxx's size word below every IDF block but left
  PXXStrAllocSize reading it, so an in-place append took the TLSF header as
  its capacity and wrote string bytes over the next block: a crash-loop at boot
  on real C3 silicon, in a config parser growing words one char at a time.
  The real path was Copy(): __pxxStrCopy builds its result through
  PXXStrAppendChar, which is the in-place append. Shape kept: TrimStr and
  NextWord over a long config-like text; several strings grown char by char, interleaved, with fresh
  allocations between appends so a write past a block lands in a neighbour;
  plus dynamic-array growth (the realloc copy) and SetLength on a string.
  Printed sums compare against the x86-64 oracle. }
var
  a, b, c, t, text: AnsiString;
  arr: array of Integer;
  i, j, sum: Integer;
  keep: array[0..15] of AnsiString;

function TrimStr(const s: AnsiString): AnsiString;
var x, y: Integer;
begin
  x := 1;
  y := Length(s);
  while (x <= y) and (s[x] = ' ') do Inc(x);
  while (y >= x) and (s[y] = ' ') do Dec(y);
  Result := Copy(s, x, y - x + 1);
end;

function NextWord(var s: AnsiString): AnsiString;
var k: Integer;
begin
  s := TrimStr(s);
  k := 1;
  while (k <= Length(s)) and (s[k] <> ' ') do Inc(k);
  Result := Copy(s, 1, k - 1);
  s := Copy(s, k, Length(s));
end;

function Sum(const s: AnsiString): Integer;
var k: Integer;
begin
  Result := 0;
  for k := 1 to Length(s) do Result := Result + Ord(s[k]) * (k mod 7 + 1);
end;

begin
  a := ''; b := ''; c := '';
  for i := 1 to 600 do
  begin
    a := a + Chr(Ord('a') + i mod 26);
    b := b + Chr(Ord('A') + (i * 7) mod 26);
    if i mod 3 = 0 then c := c + '=' + #10;
    Str(i, t);
    keep[i mod 16] := t + '/' + t;
  end;
  writeln('a ', Length(a), ' ', Sum(a));
  writeln('b ', Length(b), ' ', Sum(b));
  writeln('c ', Length(c), ' ', Sum(c));
  sum := 0;
  for i := 0 to 15 do sum := sum + Sum(keep[i]);
  writeln('keep ', sum);

  SetLength(arr, 0);
  for i := 1 to 300 do
  begin
    SetLength(arr, i);
    arr[i - 1] := i * 3;
  end;
  sum := 0;
  for i := 0 to High(arr) do sum := sum + arr[i];
  writeln('arr ', Length(arr), ' ', sum);

  t := 'xy';
  for j := 1 to 50 do
  begin
    SetLength(t, Length(t) + 3);
    t[Length(t)] := Chr(Ord('0') + j mod 10);
    t[Length(t) - 1] := '-';
    t[Length(t) - 2] := '+';
  end;
  writeln('t ', Length(t), ' ', Sum(t));
  text := '';
  for i := 1 to 120 do
  begin
    Str(i * 37, t);
    text := text + '  key' + t + ' = value' + t + ' ';
  end;
  sum := 0; j := 0;
  while Length(text) > 0 do
  begin
    t := NextWord(text);
    if t = '' then Break;
    keep[j mod 16] := Copy(t, 1, Length(t));
    sum := sum + Sum(t);
    Inc(j);
  end;
  writeln('words ', j, ' ', sum);
  writeln('done');
end.
