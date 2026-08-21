program test_read_text_char;
{ Regression: `read(f, c)` into a Char over a TEXT FILE.

  The Text read lowering is line-oriented — every destination went through
  TextReadLn — so a Char destination would have handed a ONE-BYTE slot to a
  `var AnsiString` parameter and written a string handle into it. That was
  refused with an error rather than left to corrupt memory
  (bug-p-read-text-file-into-a-char-segfaults) until the RTL half existed;
  TextReadChar now does, so the arm routes there and the refusal is gone.

  Every expectation below is FPC 3.2.2's own output for this same program, not
  reasoned about. The interleaving cases are the ones that matter: a Char arm
  that read a whole LINE and took [1] passes the first read and is silently
  wrong for every one after it, so read-then-readln must give the REST of the
  line. And `readln(f, c)` reads one character and then skips to the next line
  — 'a' then 'c' over "ab\ncd\n", not 'a' then 'b' — which is the only place
  read and readln differ observably here.
  feature-p-read-text-into-a-char-arm }

uses sysutils;

type
  TRec = record C: Char; end;

var
  tmpdir: string;
  f: Text;
  c, d: Char;
  s: string;
  i, n, ok, tot: Integer;
  arr: array[0..3] of Char;
  r: TRec;
  acc: string;
  pathA, pathB: string;

procedure Check(const nm: string; got, want: Integer);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = ', got, ' want ', want);
end;

procedure CheckS(const nm, got, want: string);
begin
  tot := tot + 1;
  if got = want then begin ok := ok + 1; writeln('ok   ', nm); end
  else writeln('FAIL ', nm, ' = [', got, '] want [', want, ']');
end;

procedure MakeFile(const path, body: string);
var g: Text;
begin
  Assign(g, path); Rewrite(g); write(g, body); Close(g);
end;

begin
  ok := 0; tot := 0;
  { two concurrent test runs must not share one scratch file — the sweep
    exports TESTTMP, and its default is /tmp so this stays byte-identical }
  tmpdir := GetEnvironmentVariable('TESTTMP');
  if tmpdir = '' then tmpdir := '/tmp';
  pathA := tmpdir + '/test_read_text_char_a.txt';
  pathB := tmpdir + '/test_read_text_char_b.txt';
  MakeFile(pathA, 'ab' + Chr(10) + 'cd' + Chr(10));
  MakeFile(pathB, 'a' + Chr(13) + Chr(10) + 'b' + Chr(10));

  { one character at a time — the newline IS a character }
  Assign(f, pathA); Reset(f);
  read(f, c); Check('read 1', Ord(c), 97);
  read(f, c); Check('read 2', Ord(c), 98);
  read(f, c); Check('read 3 (eoln)', Ord(c), 10);
  read(f, c); Check('read 4', Ord(c), 99);
  Close(f);

  { two destinations in one read, then the REST of the line }
  Assign(f, pathA); Reset(f);
  read(f, c, d); Check('read c,d first', Ord(c), 97); Check('read c,d second', Ord(d), 98);
  readln(f, s); CheckS('rest of line after 2 chars', s, '');
  readln(f, s); CheckS('next whole line', s, 'cd');
  Close(f);

  { read then readln: s gets what is LEFT of the line, not the whole line }
  Assign(f, pathA); Reset(f);
  read(f, c); Check('read before readln', Ord(c), 97);
  readln(f, s); CheckS('readln after read', s, 'b');
  read(f, c); Check('read after readln', Ord(c), 99);
  Close(f);

  { readln(f, c) reads ONE character and then skips to the next line }
  Assign(f, pathA); Reset(f);
  readln(f, c); Check('readln char 1', Ord(c), 97);
  readln(f, c); Check('readln char 2', Ord(c), 99);
  Close(f);

  { a bare readln(f) consumes a whole line }
  Assign(f, pathA); Reset(f);
  readln(f);
  readln(f, s); CheckS('after bare readln(f)', s, 'cd');
  Close(f);

  { drain with the ordinary loop, then read PAST end of file }
  Assign(f, pathA); Reset(f);
  n := 0; acc := '';
  while not Eof(f) do
  begin
    read(f, c);
    n := n + 1;
    acc := acc + Chr(Ord(c));
  end;
  Check('chars drained', n, 6);
  Check('drained bytes', Length(acc), 6);
  read(f, c); Check('past eof is #26', Ord(c), 26);
  read(f, c); Check('past eof stays #26', Ord(c), 26);
  Close(f);

  { CR is NOT swallowed by read, even though readln strips it }
  Assign(f, pathB); Reset(f);
  read(f, c); Check('crlf: char', Ord(c), 97);
  read(f, c); Check('crlf: cr survives', Ord(c), 13);
  read(f, c); Check('crlf: lf', Ord(c), 10);
  Close(f);
  Assign(f, pathB); Reset(f);
  readln(f, s); CheckS('crlf: readln strips cr', s, 'a');
  Close(f);

  { destinations that are not plain variables }
  Assign(f, pathA); Reset(f);
  for i := 0 to 3 do read(f, arr[i]);
  Check('array elem 0', Ord(arr[0]), 97);
  Check('array elem 3', Ord(arr[3]), 99);
  read(f, r.C); Check('record field', Ord(r.C), 100);
  Close(f);

  writeln('total ok ', ok, ' / ', tot);
end.
