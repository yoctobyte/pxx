{ StrUtils' word/delimiter family and SplitString —
  feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols.

  Every expectation was MEASURED by running this program under fpc 3.2.2 and
  under pxx and diffing, not derived from the names. What it pins down is that
  THREE DIFFERENT splitting models live in one unit and disagree on exactly the
  input real code has — `a,b,,c`, the row with an empty field:

    ExtractWord     a  b  c        (runs of delimiters collapse; no empty words)
    ExtractDelimited a b '' c      (every delimiter starts a field)
    ExtractSubstr   a  b  c  ''    (stops at a field but SKIPS the run after it)
    SplitString     a b '' c       (fields, as a whole array)

  So ExtractWord on CSV silently renumbers every field after the first empty
  one, and ExtractSubstr — whose name suggests the field model — follows the
  word model on its advance. Both are the kind of near-miss that reads as a
  typo and is not.

  SplitString's second argument is the other trap: it is ONE multi-character
  separator in FPC 3.2.2, not a set of characters, so 'a1b2c' split on '12'
  comes back whole while 'a12b12c' splits into three. }
program lib_strutils_words;

uses sysutils, strutils;

var
  failures: Integer;

procedure CheckStr(const got, want, what: string);
begin
  if got <> want then
  begin
    Writeln('FAIL: ', what, ' got [', got, '] want [', want, ']');
    failures := failures + 1;
  end;
end;

procedure CheckInt(got, want: Integer; const what: string);
begin
  if got <> want then
  begin
    Writeln('FAIL: ', what, ' got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

{ Rendered as <a><b><><c> so an empty field is VISIBLE — the whole point of
  these cases is telling '' apart from "absent". }
function Join(const a: TStringArray): string;
var j: Integer;
begin
  Result := '';
  for j := 0 to High(a) do Result := Result + '<' + a[j] + '>';
end;

var
  sp: TSysCharSet;
  comma: TSysCharSet;
  parts: TStringArray;
  pos: Integer;

begin
  failures := 0;
  sp := [' '];
  comma := [','];

  { ---- WordCount: a RUN of delimiters is one separator ---- }
  CheckInt(WordCount('a b c', sp), 3, 'WordCount over single spaces');
  CheckInt(WordCount('  a  b  ', sp), 2, 'WordCount ignores leading/trailing/doubled');
  CheckInt(WordCount('', sp), 0, 'WordCount of the empty string');
  CheckInt(WordCount('   ', sp), 0, 'WordCount of delimiters only');
  CheckInt(WordCount('a,b;c', [',', ';']), 3, 'WordCount with two delimiter chars');

  { ---- WordPosition: 1-based START INDEX of the Nth word, 0 when absent ---- }
  CheckInt(WordPosition(1, '  ab cd', sp), 3, 'WordPosition of the first word');
  CheckInt(WordPosition(2, '  ab cd', sp), 6, 'WordPosition of the second word');
  CheckInt(WordPosition(3, '  ab cd', sp), 0, 'WordPosition past the end is 0');
  CheckInt(WordPosition(0, 'ab', sp), 0, 'WordPosition(0) is 0, not an error');

  { ---- ExtractWord ---- }
  CheckStr(ExtractWord(1, '  ab cd', sp), 'ab', 'ExtractWord 1 skips leading delimiters');
  CheckStr(ExtractWord(2, '  ab cd', sp), 'cd', 'ExtractWord 2');
  CheckStr(ExtractWord(3, '  ab cd', sp), '', 'ExtractWord past the end is empty');
  CheckStr(ExtractWord(0, 'ab', sp), '', 'ExtractWord(0) is empty');
  { the model difference, stated as a test: word 3 of a CSV row with an empty
    field is 'c', where FIELD 3 is '' }
  CheckStr(ExtractWord(3, 'a,b,,c', comma), 'c', 'ExtractWord SKIPS the empty field');

  { ---- ExtractDelimited: every delimiter starts a field ---- }
  CheckStr(ExtractDelimited(1, 'a,b,,c', comma), 'a', 'ExtractDelimited field 1');
  CheckStr(ExtractDelimited(3, 'a,b,,c', comma), '', 'ExtractDelimited KEEPS the empty field');
  CheckStr(ExtractDelimited(4, 'a,b,,c', comma), 'c', 'ExtractDelimited field 4');
  CheckStr(ExtractDelimited(9, 'a,b,,c', comma), '', 'ExtractDelimited past the end');
  CheckStr(ExtractDelimited(0, 'abc', comma), '', 'ExtractDelimited(0)');

  { ---- ExtractSubstr: cursor form, word-style advance ---- }
  pos := 1;
  CheckStr(ExtractSubstr('a,b,,c', pos, comma), 'a', 'ExtractSubstr 1');
  CheckStr(ExtractSubstr('a,b,,c', pos, comma), 'b', 'ExtractSubstr 2');
  CheckStr(ExtractSubstr('a,b,,c', pos, comma), 'c',
           'ExtractSubstr skips the RUN of delimiters, so no empty field');
  CheckStr(ExtractSubstr('a,b,,c', pos, comma), '', 'ExtractSubstr past the end');

  { ---- SplitString: fields, empties kept, delimiter is one whole string ---- }
  parts := SplitString('a,b,,c', ',');
  CheckInt(Length(parts), 4, 'SplitString element count');
  CheckStr(Join(parts), '<a><b><><c>', 'SplitString keeps the empty field');
  parts := SplitString('', ',');
  CheckInt(Length(parts), 1, 'SplitString of the empty string yields ONE empty field');
  CheckStr(Join(parts), '<>', 'SplitString of the empty string');
  parts := SplitString('abc', '');
  CheckInt(Length(parts), 1, 'SplitString with no delimiter yields the whole string');
  CheckStr(Join(parts), '<abc>', 'SplitString with no delimiter');
  parts := SplitString(',a,', ',');
  CheckStr(Join(parts), '<><a><>', 'SplitString keeps the fields at both edges');
  parts := SplitString('a1b2c', '12');
  CheckStr(Join(parts), '<a1b2c>',
           'SplitString treats the delimiter as ONE string, not a character set');
  parts := SplitString('a12b12c', '12');
  CheckStr(Join(parts), '<a><b><c>', 'SplitString on a two-character separator');

  { the idiom the whole row exists for }
  parts := SplitString('name:x:1000:1000::/home/x:/bin/sh', ':');
  CheckInt(Length(parts), 7, 'a passwd line splits into 7 fields');
  CheckStr(parts[4], '', 'the empty GECOS field is preserved, not dropped');
  CheckStr(parts[6], '/bin/sh', 'the last field');

  if failures = 0 then Writeln('STRUTILSWORDS OK')
  else Writeln('STRUTILSWORDS ', failures, ' FAILURES');
end.
