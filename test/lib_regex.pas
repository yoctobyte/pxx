program lib_regex;
{ Track B smoke for lib/rtl/regex.pas. Expectations are what CPython's `re`
  produces for the same pattern/subject pairs, including every pattern the
  songformatter target actually uses. }

uses regex;

var
  failures: Integer;

procedure CheckBool(const name: AnsiString; got, want: Boolean);
begin
  if got = want then
    WriteLn('ok   ', name)
  else
  begin
    WriteLn('FAIL ', name, ': got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

procedure CheckStr(const name, got, want: AnsiString);
begin
  if got = want then
    WriteLn('ok   ', name)
  else
  begin
    WriteLn('FAIL ', name, ': got "', got, '" want "', want, '"');
    failures := failures + 1;
  end;
end;

procedure CheckInt(const name: AnsiString; got, want: Integer);
begin
  if got = want then
    WriteLn('ok   ', name)
  else
  begin
    WriteLn('FAIL ', name, ': got ', got, ' want ', want);
    failures := failures + 1;
  end;
end;

{ ---- helpers over the one-shot surface ---------------------------------- }

function MatchesAnchored(const pat, s: AnsiString): Boolean;
begin
  MatchesAnchored := ReQuickMatch(pat, s, RE_NONE);
end;

function FullMatches(const pat, s: AnsiString): Boolean;
var re: TRegex; m: TReMatch;
begin
  re := ReCompile(pat, RE_NONE);
  m := ReFullMatch(re, s);
  FullMatches := m.matched;
end;

function GroupOf(const pat, s: AnsiString; n: Integer): AnsiString;
var re: TRegex; m: TReMatch;
begin
  re := ReCompile(pat, RE_NONE);
  m := ReMatch(re, s);
  GroupOf := ReGroup(m, s, n);
end;

function SearchGroup(const pat, s: AnsiString; n: Integer): AnsiString;
var re: TRegex; m: TReMatch;
begin
  re := ReCompile(pat, RE_NONE);
  m := ReSearch(re, s);
  SearchGroup := ReGroup(m, s, n);
end;

function CountAll(const pat, s: AnsiString): Integer;
var re: TRegex; ms: array[0..63] of TReMatch;
begin
  re := ReCompile(pat, RE_NONE);
  CountAll := ReFindAll(re, s, ms, 64);
end;

function JoinAll(const pat, s: AnsiString): AnsiString;
var re: TRegex; ms: array[0..63] of TReMatch; n, i: Integer; acc: AnsiString;
begin
  re := ReCompile(pat, RE_NONE);
  n := ReFindAll(re, s, ms, 64);
  acc := '';
  for i := 0 to n - 1 do
  begin
    if i > 0 then acc := acc + ',';
    acc := acc + ReGroup(ms[i], s, 0);
  end;
  JoinAll := acc;
end;

function SubAll(const pat, s, repl: AnsiString): AnsiString;
var re: TRegex;
begin
  re := ReCompile(pat, RE_NONE);
  SubAll := ReReplace(re, s, repl, -1);
end;

var
  re: TRegex;
  m: TReMatch;
  chordPattern: AnsiString;

begin
  failures := 0;

  { ---- literals, dot, anchors ---- }
  CheckBool('literal match', MatchesAnchored('abc', 'abcdef'), True);
  CheckBool('literal mismatch', MatchesAnchored('abc', 'abx'), False);
  CheckBool('dot', MatchesAnchored('a.c', 'axc'), True);
  CheckBool('dot not newline', MatchesAnchored('a.c', 'a' + #10 + 'c'), False);
  CheckBool('anchored ^', FullMatches('^abc$', 'abc'), True);
  CheckBool('full match rejects tail', FullMatches('abc', 'abcd'), False);

  { ---- classes ---- }
  CheckBool('class range', MatchesAnchored('[A-G]', 'D'), True);
  CheckBool('class range miss', MatchesAnchored('[A-G]', 'H'), False);
  CheckBool('class negated', MatchesAnchored('[^A-G]', 'H'), True);
  CheckBool('class literal dash', MatchesAnchored('[a-]', '-'), True);
  CheckBool('class escape range', MatchesAnchored('[\x00-\x1f]', #9), True);
  CheckBool('class escape range miss', MatchesAnchored('[\x00-\x1f]', 'a'), False);
  CheckBool('digit shorthand', MatchesAnchored('\d', '7'), True);
  CheckBool('non-digit shorthand', MatchesAnchored('\D', 'x'), True);
  CheckBool('space shorthand', MatchesAnchored('\s', ' '), True);

  { ---- quantifiers ---- }
  CheckBool('star zero', FullMatches('ab*c', 'ac'), True);
  CheckBool('star many', FullMatches('ab*c', 'abbbc'), True);
  CheckBool('plus needs one', FullMatches('ab+c', 'ac'), False);
  CheckBool('plus many', FullMatches('ab+c', 'abbc'), True);
  CheckBool('optional', FullMatches('ab?c', 'ac'), True);
  CheckBool('counted exact', FullMatches('ab{2}c', 'abbc'), True);
  CheckBool('counted exact rejects', FullMatches('ab{2}c', 'abc'), False);
  CheckBool('counted range', FullMatches('ab{1,3}c', 'abbc'), True);
  CheckBool('counted range rejects', FullMatches('ab{1,3}c', 'abbbbc'), False);
  CheckBool('counted open', FullMatches('ab{2,}c', 'abbbbc'), True);

  { greedy vs non-greedy: the whole point of the split ordering }
  CheckStr('greedy takes all', GroupOf('<(.*)>', '<a><b>', 1), 'a><b');
  CheckStr('non-greedy stops early', GroupOf('<(.*?)>', '<a><b>', 1), 'a');

  { ---- alternation ---- }
  CheckBool('alt first', MatchesAnchored('cat|dog', 'dogma'), True);
  CheckBool('alt second', MatchesAnchored('cat|dog', 'catalog'), True);
  CheckBool('alt neither', MatchesAnchored('cat|dog', 'bird'), False);
  { longest-first ordering matters, as in Python: IV before I }
  CheckStr('alt order IV', JoinAll('IV|IX|I|V|X', 'IV'), 'IV');
  CheckStr('alt order mixed', JoinAll('IV|IX|I|V|X', 'XIV'), 'X,IV');

  { ---- groups ---- }
  CheckStr('group 1', GroupOf('([A-G])([b#]?)', 'C#', 1), 'C');
  CheckStr('group 2', GroupOf('([A-G])([b#]?)', 'C#', 2), '#');
  CheckStr('group absent', GroupOf('([A-G])([b#]?)', 'C', 2), '');
  CheckStr('non-capturing', GroupOf('([A-G])(?:maj)?7', 'Cmaj7', 1), 'C');

  { ---- find all / replace ---- }
  CheckInt('findall count', CountAll('[A-G]', 'C D E'), 3);
  CheckStr('findall joined', JoinAll('[A-G][b#]?', 'C# Db E'), 'C#,Db,E');
  CheckStr('replace all', SubAll('\s+', 'a  b   c', ' '), 'a b c');
  CheckStr('replace group ref', SubAll('([A-G])#', 'C# D', '\1sharp'),
           'Csharp D');
  CheckStr('replace strips class', SubAll('[<>:"/\\|?*]', 'a<b>c', ''), 'abc');

  { ---- flags ---- }
  re := ReCompile('abc', RE_IGNORECASE);
  m := ReMatch(re, 'ABC');
  CheckBool('ignorecase literal', m.matched, True);
  re := ReCompile('[a-c]+', RE_IGNORECASE);
  m := ReFullMatch(re, 'ABC');
  CheckBool('ignorecase class', m.matched, True);
  re := ReCompile('a . c   # a commented pattern' + #10 + ' \d', RE_VERBOSE);
  m := ReFullMatch(re, 'axc7');
  CheckBool('verbose skips layout', m.matched, True);
  re := ReCompile('a.c', RE_DOTALL);
  m := ReFullMatch(re, 'a' + #10 + 'c');
  CheckBool('dotall', m.matched, True);

  { ---- error reporting, not silent mis-matching ---- }
  re := ReCompile('a(b', RE_NONE);
  CheckBool('unbalanced ( fails', re.ok, False);
  re := ReCompile('[a-', RE_NONE);
  CheckBool('unterminated class fails', re.ok, False);
  re := ReCompile('*x', RE_NONE);
  CheckBool('bare quantifier fails', re.ok, False);
  re := ReCompile('(?=x)', RE_NONE);
  CheckBool('lookahead reported unsupported', re.ok, False);
  re := ReCompile('(a)\1', RE_NONE);
  CheckBool('backreference reported unsupported', re.ok, False);

  { ---- the songformatter patterns, verbatim ---- }
  CheckStr('chord root split',
           GroupOf('^([A-G][b#]?)(.*?)(?:/([A-G][b#]?))?$', 'C#m7/G', 1), 'C#');
  CheckStr('chord bass split',
           GroupOf('^([A-G][b#]?)(.*?)(?:/([A-G][b#]?))?$', 'C#m7/G', 3), 'G');
  chordPattern := '^[A-Ga-g][b#]?[1-7,9/#bMmajsuo\+di-]*$';
  CheckBool('chord accepted', FullMatches(chordPattern, 'Am7'), True);
  { CPython agrees: the class has lower-case 'b' but not upper-case 'B', so a
    slash chord with an upper-case bass note is NOT accepted by this pattern.
    Kept as a test because it pins the case sensitivity of the class. }
  CheckBool('chord slash upper bass rejected',
            FullMatches(chordPattern, 'G/B'), False);
  CheckBool('chord slash lower bass accepted',
            FullMatches(chordPattern, 'G/b'), True);
  CheckBool('chord rejected word', FullMatches(chordPattern, 'the'), False);
  CheckStr('tuning notes', JoinAll('([A-G](#|b)?)', 'EADGBE'), 'E,A,D,G,B,E');
  CheckBool('integer param', FullMatches('^-?\d+$', '-42'), True);
  CheckBool('integer param rejects', FullMatches('^-?\d+$', '4x'), False);
  CheckStr('sanitize filename',
           SubAll('[<>:"/\\|?*]', 'A/B:C', ''), 'ABC');
  CheckStr('chord token split',
           JoinAll('[A-G][#b]?(?:maj7|M7|m9|m7|m6|7|dim|aug|sus4|sus2|m)?',
                   'Cmaj7 Am7 G'), 'Cmaj7,Am7,G');

  WriteLn('');
  if failures = 0 then
    WriteLn('REGEX OK')
  else
    WriteLn('REGEX FAILURES: ', failures);
end.
