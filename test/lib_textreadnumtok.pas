{ TextReadNumTok / TextReadStrTo — the two cursor-preserving readers FPC's
  `read(f, number)` and `read(f, s)` are built from.

  Every expectation here was MEASURED against FPC 3.2.2, cursor position
  included: the oracle program ran `read(t, n)` / `read(t, s)` on each file and
  then drained the remainder one character at a time, so `rest` below is where
  FPC actually left the cursor, not where it seemed reasonable for it to be.
  That is the whole subject — the bug these replace
  (bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line) was a reader
  that got the VALUE right for one file shape and the cursor wrong for all of
  them, so a test that only checked values would have passed it.

  Two properties carry all the rest:

    * a numeric token skips whitespace INCLUDING line breaks, then stops at the
      next whitespace byte and PUTS IT BACK — '42 3' yields '42' with ' 3' still
      to come, which is what makes `read(t, n); read(t, m)` give 42 and 3;
    * a string read stops BEFORE the terminator and never steps over it, so
      repeating it yields '' forever until a readln crosses the line ending.

  The empty-token case is deliberate and matches FPC: at end of file, or with
  only whitespace left, the token is '' and the caller's Val leaves 0. }
program lib_textreadnumtok;

uses textfile, sysutils;

var
  failures: Integer;
  path: AnsiString;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    writeln('FAIL: ', what, ' got <', got, '> want <', want, '>');
    failures := failures + 1;
  end;
end;

procedure WriteFile(const content: AnsiString);
var f: Text;
begin
  Assign(f, path);
  Rewrite(f);
  TextWrite(f, content);
  Close(f);
end;

{ Whatever is left of the file after the read under test, with the invisible
  bytes spelled out — this is the half of the answer a value-only check misses. }
function Rest(var f: Text): AnsiString;
var c: Char; s: AnsiString;
begin
  s := '';
  while not Eof(f) do
  begin
    TextReadChar(f, c);
    if c = #10 then s := s + '\n'
    else if c = #13 then s := s + '\r'
    else if c = #9 then s := s + '\t'
    else if c = ' ' then s := s + '_'
    else s := s + c;
  end;
  Rest := s;
end;

{ One numeric read, reported as FPC's own oracle reported it: the value the
  caller's Val produces, then the cursor. }
function NumRead(const content: AnsiString): AnsiString;
var f: Text; tok: AnsiString; code: Integer; v: Int64;
begin
  WriteFile(content);
  Assign(f, path);
  Reset(f);
  TextReadNumTok(f, tok);
  Val(tok, v, code);
  if code <> 0 then v := 0;
  NumRead := IntToStr(v) + ' rest=[' + Rest(f) + ']';
  Close(f);
end;

function FloatRead(const content: AnsiString): AnsiString;
var f: Text; tok, shown: AnsiString; code: Integer; d: Double;
begin
  WriteFile(content);
  Assign(f, path);
  Reset(f);
  TextReadNumTok(f, tok);
  Val(tok, d, code);
  if code <> 0 then d := 0;
  Str(d:0:3, shown);
  FloatRead := shown + ' rest=[' + Rest(f) + ']';
  Close(f);
end;

function StrRead(const content: AnsiString): AnsiString;
var f: Text; s: AnsiString;
begin
  WriteFile(content);
  Assign(f, path);
  Reset(f);
  TextReadStrTo(f, s);
  StrRead := '[' + s + '] rest=[' + Rest(f) + ']';
  Close(f);
end;

{ Two numeric reads in a row — the shape the bug made impossible. }
function TwoNums(const content: AnsiString): AnsiString;
var f: Text; tok: AnsiString; code: Integer; a, b: Int64;
begin
  WriteFile(content);
  Assign(f, path);
  Reset(f);
  TextReadNumTok(f, tok); Val(tok, a, code); if code <> 0 then a := 0;
  TextReadNumTok(f, tok); Val(tok, b, code); if code <> 0 then b := 0;
  TwoNums := IntToStr(a) + ' ' + IntToStr(b);
  Close(f);
end;

{ Two string reads in a row: the second must be EMPTY, because the first
  stopped before the terminator and nothing has crossed it. }
function TwoStrs(const content: AnsiString): AnsiString;
var f: Text; s1, s2: AnsiString;
begin
  WriteFile(content);
  Assign(f, path);
  Reset(f);
  TextReadStrTo(f, s1);
  TextReadStrTo(f, s2);
  TwoStrs := '[' + s1 + '][' + s2 + ']';
  Close(f);
end;

{ read(f, s); readln(f); read(f, s) — the classic idiom that skipped every
  other line while `read` and `readln` lowered to the same call. }
function StrReadLnStr(const content: AnsiString): AnsiString;
var f: Text; s1, s2, junk: AnsiString;
begin
  WriteFile(content);
  Assign(f, path);
  Reset(f);
  TextReadStrTo(f, s1);
  TextReadLn(f, junk);      { readln(f): step over the terminator }
  TextReadStrTo(f, s2);
  StrReadLnStr := '[' + s1 + '][' + s2 + ']';
  Close(f);
end;

begin
  failures := 0;
  { Two concurrent test runs must not share one scratch file. The sweep exports
    TESTTMP; GetTempDir is the fallback, so nothing here hardcodes a /tmp path
    (tools/testmgr_hardcoded_tmp_devtest.py is a ratchet against exactly that). }
  path := GetEnvironmentVariable('TESTTMP');
  if path = '' then path := GetTempDir;
  if (Length(path) > 0) and (path[Length(path)] <> '/') then path := path + '/';
  path := path + 'lib_textreadnumtok.txt';

  { --- numeric token: value AND cursor, both from FPC --- }
  CheckStr(NumRead('42'#10),        '42 rest=[\n]',      'num: terminator is not eaten');
  CheckStr(NumRead('42 3'#10),      '42 rest=[_3\n]',    'num: delimiting blank is not eaten');
  CheckStr(NumRead('42'#9'3'#10),   '42 rest=[\t3\n]',   'num: tab delimits');
  CheckStr(NumRead('   42 3'#10),   '42 rest=[_3\n]',    'num: leading blanks skipped');
  { Both blanks are still there: the token stops at the FIRST one and puts it
    back. Measured — an expectation of one blank was wrong and FPC said so. }
  CheckStr(NumRead('42  '#10),      '42 rest=[__\n]',    'num: trailing blanks are not part of it');
  CheckStr(NumRead(#10#10'42'#10),  '42 rest=[\n]',      'num: blank lines are whitespace');
  CheckStr(NumRead(' '#9#10' 42'#10), '42 rest=[\n]',    'num: mixed leading whitespace');
  CheckStr(NumRead('42'#13#10'9'#10), '42 rest=[\r\n9\n]', 'num: CR delimits and stays');
  CheckStr(NumRead('42'),           '42 rest=[]',        'num: no trailing newline');
  CheckStr(NumRead(''),             '0 rest=[]',         'num: empty file gives 0');
  CheckStr(NumRead('   '#10'  '),   '0 rest=[]',         'num: only whitespace gives 0');
  CheckStr(NumRead('-42 3'#10),     '-42 rest=[_3\n]',   'num: sign belongs to the token');
  CheckStr(NumRead('+42 3'#10),     '42 rest=[_3\n]',    'num: leading plus');

  CheckStr(FloatRead('2.5 3'#10),   '2.500 rest=[_3\n]', 'real: fraction');
  CheckStr(FloatRead('2.5e3 x'#10), '2500.000 rest=[_x\n]', 'real: exponent is one token');
  CheckStr(FloatRead('7 x'#10),     '7.000 rest=[_x\n]', 'real: an integer literal reads as a real');

  CheckStr(TwoNums('42 3'#10),      '42 3',              'num: two on one line');
  CheckStr(TwoNums('1'#10'2'#10),   '1 2',               'num: two across a line break');
  CheckStr(TwoNums('42'#10),        '42 0',              'num: the second runs out and gives 0');

  { --- string to the terminator: stops BEFORE it, every time --- }
  CheckStr(StrRead('L1'#10'L2'#10), '[L1] rest=[\nL2\n]', 'str: stops before the newline');
  CheckStr(StrRead('L1'#13#10),     '[L1] rest=[\r\n]',   'str: stops at the CR');
  CheckStr(StrRead(#10'L2'#10),     '[] rest=[\nL2\n]',   'str: an empty line reads empty and does not advance');
  CheckStr(StrRead('L1'),           '[L1] rest=[]',       'str: no trailing newline');
  CheckStr(StrRead(''),             '[] rest=[]',         'str: empty file');

  CheckStr(TwoStrs('L1'#10'L2'#10),      '[L1][]',   'str: a repeat gives empty, not the next line');
  CheckStr(StrReadLnStr('L1'#10'L2'#10), '[L1][L2]', 'str: read/readln/read walks consecutive lines');

  { --- the tokenisers share their cursor with TextReadChar and TextReadLn --- }
  CheckStr(NumRead('42 abc'#10),    '42 rest=[_abc\n]',   'num then the rest of the line');

  DeleteFile(path);
  if failures = 0 then
    writeln('TEXTNUMTOK OK')
  else
  begin
    writeln('TEXTNUMTOK FAILURES: ', failures);
    Halt(1);
  end;
end.
