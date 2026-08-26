program test_read_text_value_cursor;
{ Regression: `read[ln](f, ...)` over a TEXT FILE must leave the CURSOR where
  FPC leaves it, not only produce the right value.

  The Text read lowering used to send BOTH the numeric and the string
  destination through TextReadLn, which eats the line AND its terminator. So
  `readln(t, n, m)` on '42 3' gave 0 0 (Val wants the string to be the number
  and nothing else, and the failure was discarded), '42  ' with trailing blanks
  gave 0, and `read(f, s)` was indistinguishable from `readln(f, s)` — the
  classic `read(f, s); readln(f)` idiom silently skipped every other line.
  bug-p-read-text-lowers-every-destination-to-a-whole-line-read

  Every arm is now cursor-preserving: TextReadNumTok takes one
  whitespace-delimited token and pushes the delimiter back, TextReadStrTo reads
  up to but NOT over the terminator, TextReadChar takes one character. `readln`
  is then one unconditional end-of-line skip after whatever the destinations
  were — the per-arm special case that used to decide whether to emit it is
  gone.

  A value-only test cannot see this bug's second half, so every case below
  DRAINS the rest of the file one character at a time and asserts what is left.
  `Rest` is what makes the cursor visible rather than inferred: without it,
  `read(t, n)` on '42 3' looks correct at n=42 while the cursor is a line too
  far. Every expectation is FPC 3.2.2's own output for this same program,
  measured with the same drain, not reasoned about. }

uses sysutils;

var
  tmpdir: string;
  t: Text;
  n, m, k, ok, tot: Integer;
  d: Double;
  s, s2: string;
  c: Char;
  pathA: string;

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

{ Make the remaining bytes visible so a whitespace-only difference cannot
  masquerade as agreement. }
function Vis(const a: string): string;
var i: Integer; ch: Char; r: string;
begin
  r := '';
  for i := 1 to Length(a) do
  begin
    ch := a[i];
    if ch = Chr(10) then r := r + '<LF>'
    else if ch = Chr(13) then r := r + '<CR>'
    else if ch = ' ' then r := r + '<SP>'
    else if ch = Chr(9) then r := r + '<TAB>'
    else r := r + ch;
  end;
  Vis := r;
end;

{ Everything the file still holds, one character at a time — the cursor. }
function Rest(var f: Text): string;
var ch: Char; acc: string;
begin
  acc := '';
  while not Eof(f) do begin read(f, ch); acc := acc + Chr(Ord(ch)); end;
  Rest := Vis(acc);
end;

function LF: string;
begin
  LF := Chr(10);
end;

function CRLF: string;
begin
  CRLF := Chr(13) + Chr(10);
end;

begin
  ok := 0; tot := 0;
  tmpdir := GetEnvironmentVariable('TESTTMP');
  if tmpdir = '' then tmpdir := '/tmp';
  pathA := tmpdir + '/test_read_text_value_cursor.txt';

  { --- the headline case: two numbers on one line --- }
  MakeFile(pathA, '42 3' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; m := -1; readln(t, n, m);
  Check('readln two: n', n, 42);
  Check('readln two: m', m, 3);
  CheckS('readln two: rest', Rest(t), '');
  Close(t);

  { one number, trailing blanks. FPC stops at the FIRST blank, so BOTH survive
    — this row was measured, an expectation of one blank was wrong. }
  MakeFile(pathA, '42  ' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; read(t, n);
  Check('read trailing-sp: n', n, 42);
  CheckS('read trailing-sp: rest', Rest(t), '<SP><SP><LF>');
  Close(t);

  { readln DOES step over the rest of the line after a numeric destination }
  MakeFile(pathA, '42  ' + LF + '9' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; readln(t, n);
  Check('readln trailing-sp: n', n, 42);
  CheckS('readln trailing-sp: rest', Rest(t), '9<LF>');
  Close(t);

  { two separate reads share the cursor }
  MakeFile(pathA, '42 3' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; m := -1; read(t, n); read(t, m);
  Check('read,read: n', n, 42);
  Check('read,read: m', m, 3);
  CheckS('read,read: rest', Rest(t), '<LF>');
  Close(t);

  { Eoln after a numeric read — the row a value-only test cannot see }
  MakeFile(pathA, '42 3' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; read(t, n);
  Check('read then eoln (mid-line)', Ord(Eoln(t)), 0);
  Close(t);
  MakeFile(pathA, '42' + LF + 'x' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; read(t, n);
  Check('read then eoln (at eol)', Ord(Eoln(t)), 1);
  CheckS('read then eoln: rest', Rest(t), '<LF>x<LF>');
  Close(t);

  { a numeric token skips leading whitespace INCLUDING line breaks }
  MakeFile(pathA, LF + LF + '42' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; read(t, n);
  Check('blank lines are whitespace: n', n, 42);
  CheckS('blank lines are whitespace: rest', Rest(t), '<LF>');
  Close(t);

  { ...so one readln can span lines }
  MakeFile(pathA, '42' + LF + '  3' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; m := -1; readln(t, n, m);
  Check('readln across lines: n', n, 42);
  Check('readln across lines: m', m, 3);
  CheckS('readln across lines: rest', Rest(t), '');
  Close(t);

  { three destinations, and the skip stops at the END of the line they came from }
  MakeFile(pathA, '1 2 3' + LF + '9' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; m := -1; k := -1; readln(t, n, m, k);
  Check('readln three: n', n, 1);
  Check('readln three: m', m, 2);
  Check('readln three: k', k, 3);
  CheckS('readln three: rest', Rest(t), '9<LF>');
  Close(t);

  { the table loop — the single commonest reason to open a text file }
  MakeFile(pathA, '1 2' + LF + '3 4' + LF + '5 6' + LF);
  Assign(t, pathA); Reset(t);
  s := '';
  while not Eof(t) do
  begin
    n := -1; m := -1; readln(t, n, m);
    s := s + IntToStr(n) + ',' + IntToStr(m) + ';';
  end;
  CheckS('table loop', s, '1,2;3,4;5,6;');
  Close(t);

  { a real and an integer in one readln }
  MakeFile(pathA, '2.5 7' + LF);
  Assign(t, pathA); Reset(t);
  d := -1; n := -1; readln(t, d, n);
  Check('readln real (x100)', Round(d * 100), 250);
  Check('readln real: n', n, 7);
  Close(t);

  { a number then the REST of the line as a string — the delimiting blank is
    part of what the string arm gets, because the number arm left it parked }
  MakeFile(pathA, '42 abc' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; s := 'X'; read(t, n); readln(t, s);
  Check('num then str: n', n, 42);
  CheckS('num then str: s', s, ' abc');
  CheckS('num then str: rest', Rest(t), '');
  Close(t);

  { a number then ONE character: the blank, not the '3' }
  MakeFile(pathA, '42 3' + LF);
  Assign(t, pathA); Reset(t);
  n := -1; c := 'X'; read(t, n); read(t, c);
  Check('num then char: n', n, 42);
  Check('num then char: c', Ord(c), 32);
  CheckS('num then char: rest', Rest(t), '3<LF>');
  Close(t);

  { --- the string arm: read stops BEFORE the terminator --- }
  MakeFile(pathA, 'L1' + LF + 'L2' + LF + 'L3' + LF);
  Assign(t, pathA); Reset(t);
  s := 'X'; s2 := 'X'; read(t, s); read(t, s2);
  CheckS('read str twice: first', s, 'L1');
  CheckS('read str twice: second is empty', s2, '');
  CheckS('read str twice: rest', Rest(t), '<LF>L2<LF>L3<LF>');
  Close(t);

  { ...so the read/readln idiom walks the lines instead of skipping every other one }
  Assign(t, pathA); Reset(t);
  s := 'X'; s2 := 'X'; read(t, s); readln(t); read(t, s2);
  CheckS('read,readln,read: first', s, 'L1');
  CheckS('read,readln,read: second', s2, 'L2');
  CheckS('read,readln,read: rest', Rest(t), '<LF>L3<LF>');
  Close(t);

  { readln(f, s) is unchanged: the line, and over the terminator }
  Assign(t, pathA); Reset(t);
  s := 'X'; s2 := 'X'; readln(t, s); readln(t, s2);
  CheckS('readln str twice: first', s, 'L1');
  CheckS('readln str twice: second', s2, 'L2');
  CheckS('readln str twice: rest', Rest(t), 'L3<LF>');
  Close(t);

  { an empty line is an empty string, not a skipped one }
  MakeFile(pathA, LF + 'L2' + LF);
  Assign(t, pathA); Reset(t);
  s := 'X'; s2 := 'X'; readln(t, s); readln(t, s2);
  CheckS('readln empty line: first', s, '');
  CheckS('readln empty line: second', s2, 'L2');
  Close(t);

  { CRLF: the string arm stops AT the CR, and readln's skip steps over CR+LF }
  MakeFile(pathA, 'L1' + CRLF + 'L2' + CRLF);
  Assign(t, pathA); Reset(t);
  s := 'X'; read(t, s);
  CheckS('crlf read str', s, 'L1');
  CheckS('crlf read str: rest', Rest(t), '<CR><LF>L2<CR><LF>');
  Close(t);
  Assign(t, pathA); Reset(t);
  s := 'X'; s2 := 'X'; readln(t, s); readln(t, s2);
  CheckS('crlf readln str: first', s, 'L1');
  CheckS('crlf readln str: second', s2, 'L2');
  CheckS('crlf readln str: rest', Rest(t), '');
  Close(t);
  MakeFile(pathA, '42' + CRLF + '7' + CRLF);
  Assign(t, pathA); Reset(t);
  n := -1; m := -1; readln(t, n); readln(t, m);
  Check('crlf readln num: first', n, 42);
  Check('crlf readln num: second', m, 7);
  Close(t);

  { --- the char arm and the bare readln, unchanged by the collapse --- }
  MakeFile(pathA, 'ab' + LF + 'cd' + LF);
  Assign(t, pathA); Reset(t);
  readln(t, c); Check('readln char 1', Ord(c), 97);
  readln(t, c); Check('readln char 2', Ord(c), 99);
  Close(t);
  Assign(t, pathA); Reset(t);
  s := 'X'; readln(t); readln(t, s);
  CheckS('bare readln then str', s, 'cd');
  Close(t);
  Assign(t, pathA); Reset(t);
  c := 'X'; s := 'X'; read(t, c); readln(t, s);
  Check('char then str: c', Ord(c), 97);
  CheckS('char then str: s', s, 'b');
  CheckS('char then str: rest', Rest(t), 'cd<LF>');
  Close(t);

  DeleteFile(pathA);
  writeln('total ok ', ok, ' / ', tot);
end.
