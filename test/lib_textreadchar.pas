{ TextReadChar — FPC's read(f, c) — consumes ONE character, not a line.

  Every expectation here was measured against FPC on the same three files, not
  reasoned about: `for i := 1 to 4 do Read(f, c)` over "ab\ncd\n" prints
  [97][98][10][99], so the newline IS a character; reading past end of file
  yields #26 forever with no I/O error; CR is NOT swallowed by Read even though
  Readln strips it.

  The interleaving cases are the ones that matter. A Char arm that read a whole
  LINE and returned s[1] would pass the first read and fail every one after it
  (bug-p-read-text-file-into-a-char-segfaults chose a compile error over exactly
  that silent wrong answer), so read-then-readln must give the REST of the line,
  and readln-then-read must give the first character of the NEXT one. }
program lib_textreadchar;

uses textfile, sysutils;

var
  failures: Integer;

procedure Check(ok: Boolean; const what: string);
begin
  if not ok then
  begin
    writeln('FAIL: ', what);
    failures := failures + 1;
  end;
end;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got <', got, '> want <', want, '>');
    failures := failures + 1;
  end;
end;

procedure WriteFile(const path, content: AnsiString);
var f: Text;
begin
  Assign(f, path);
  Rewrite(f);
  TextWrite(f, content);
  Close(f);
end;

{ every character to end of file, as space-separated ordinals }
function DrainOrds(const path: AnsiString): AnsiString;
var f: Text; c: Char; s: AnsiString;
begin
  Assign(f, path);
  Reset(f);
  s := '';
  while not Eof(f) do
  begin
    TextReadChar(f, c);
    s := s + IntToStr(Ord(c)) + ' ';
  end;
  Close(f);
  Result := s;
end;

var
  p1, p2, p3: AnsiString;
  f: Text;
  c: Char;
  s: AnsiString;
  i: Integer;
  acc: AnsiString;
begin
  failures := 0;
  p1 := '/tmp/lib_textreadchar_1.txt';
  p2 := '/tmp/lib_textreadchar_2.txt';
  p3 := '/tmp/lib_textreadchar_3.txt';
  WriteFile(p1, 'ab' + Chr(10) + 'cd' + Chr(10));
  WriteFile(p2, 'xy');                                   { no trailing newline }
  WriteFile(p3, 'a' + Chr(13) + Chr(10) + 'b' + Chr(10));

  { FPC: [97][98][10][99] — the newline is a character like any other }
  Assign(f, p1); Reset(f);
  acc := '';
  for i := 1 to 4 do
  begin
    TextReadChar(f, c);
    acc := acc + '[' + IntToStr(Ord(c)) + ']';
  end;
  Close(f);
  CheckStr(acc, '[97][98][10][99]', 'four chars of "ab\ncd\n"');

  { FPC: c=97 s=<b> then s2=<cd> — read leaves the REST of the line for readln }
  Assign(f, p1); Reset(f);
  TextReadChar(f, c);
  TextReadLn(f, s);
  Check(Ord(c) = 97, 'read-then-readln: first char');
  CheckStr(s, 'b', 'read-then-readln: rest of line 1');
  TextReadLn(f, s);
  CheckStr(s, 'cd', 'read-then-readln: line 2');
  Close(f);

  { FPC: s=<ab> c=99 — readln lands the cursor on the next line's first char }
  Assign(f, p1); Reset(f);
  TextReadLn(f, s);
  TextReadChar(f, c);
  CheckStr(s, 'ab', 'readln-then-read: line 1');
  Check(Ord(c) = 99, 'readln-then-read: first char of line 2');
  Close(f);

  { FPC character loops }
  CheckStr(DrainOrds(p1), '97 98 10 99 100 10 ', 'char loop over "ab\ncd\n"');
  CheckStr(DrainOrds(p2), '120 121 ', 'char loop, no trailing newline');
  CheckStr(DrainOrds(p3), '97 13 10 98 10 ', 'char loop keeps CR');

  { FPC: [120][121][26][26] — past end of file is ^Z, not an error or a hang }
  Assign(f, p2); Reset(f);
  acc := '';
  for i := 1 to 4 do
  begin
    TextReadChar(f, c);
    acc := acc + '[' + IntToStr(Ord(c)) + ']';
  end;
  Check(IOResult = 0, 'reading past EOF sets no I/O error');
  Close(f);
  CheckStr(acc, '[120][121][26][26]', 'reads past end of file');

  Erase(f);
  Assign(f, p1); Erase(f);
  Assign(f, p3); Erase(f);

  if failures = 0 then writeln('TEXTREADCHAR OK')
  else writeln('TEXTREADCHAR ', failures, ' FAILURES');
end.
