program lib_strutil;
{ Smoke for the SysUtils string helpers added 2026-06-24: CompareStr/CompareText/
  SameText, TrimLeft/TrimRight, TryStrToInt, StringReplace, QuotedStr. }
uses sysutils, strutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var v: Integer; emptyStr: string;
begin
  emptyStr := '';
  SayBool('cmp-lt', CompareStr('apple', 'banana') < 0);
  SayBool('cmp-gt', CompareStr('b', 'a') > 0);
  SayBool('cmp-eq', CompareStr('abc', 'abc') = 0);
  SayBool('cmp-prefix', CompareStr('ab', 'abc') < 0);
  SayBool('cmptext', CompareText('AbC', 'abc') = 0);
  SayBool('sametext', SameText('HeLLo', 'hello') and not SameText('a', 'b'));

  SayBool('trimleft', TrimLeft('   hi') = 'hi');
  SayBool('trimright', TrimRight('hi   ') = 'hi');

  v := -1;
  SayBool('try-ok', TryStrToInt('-42', v) and (v = -42));
  SayBool('try-plus', TryStrToInt('+7', v) and (v = 7));
  SayBool('try-bad', not TryStrToInt('4x', v));
  SayBool('try-empty', not TryStrToInt('   ', v));

  SayBool('replace-all', StringReplace('a.b.c', '.', '-', [rfReplaceAll]) = 'a-b-c');
  SayBool('replace-first', StringReplace('a.b.c', '.', '-', []) = 'a-b.c');
  SayBool('replace-ci', StringReplace('aXbXc', 'x', '_', [rfIgnoreCase, rfReplaceAll]) = 'a_b_c');
  SayBool('replace-nomatch', StringReplace('abc', 'z', '_', [rfReplaceAll]) = 'abc');
  SayBool('replace-grow', StringReplace('a.b', '.', '<>', [rfReplaceAll]) = 'a<>b');
  SayBool('replace-delete', StringReplace('a-b-c', '-', '', [rfReplaceAll]) = 'abc');
  SayBool('replace-multi', StringReplace('xAByAB', 'AB', 'Z', [rfReplaceAll]) = 'xZyZ');
  SayBool('replace-first-rest', StringReplace('a.b.c', '.', '-', []) = 'a-b.c');

  SayBool('quoted', QuotedStr('it''s') = '''it''''s''');

  { case-fold + Copy + Pad (SetLength/Move rewrites — lock in behaviour) }
  SayBool('upper', UpperCase('aB3z') = 'AB3Z');
  SayBool('lower', LowerCase('aB3Z') = 'ab3z');
  SayBool('upper-empty', UpperCase('') = '');
  SayBool('copy-mid', Copy('abcdef', 2, 3) = 'bcd');
  SayBool('copy-clamp', Copy('abc', 2, 99) = 'bc');
  SayBool('copy-oob', Copy('abc', 9, 2) = '');
  SayBool('copy-zero', Copy('abc', 2, 0) = '');
  SayBool('padleft', PadLeft('42', 5, '0') = '00042');
  SayBool('padright', PadRight('42', 5, '.') = '42...');
  SayBool('padleft-empty', PadLeft('', 3, 'x') = 'xxx');
  SayBool('pad-nogrow', PadLeft('toolong', 3, ' ') = 'toolong');

  { Pos with an EMPTY needle is 0, not 1. Returning 1 is C's strstr convention
    and it silently breaks the common `if Pos(sep, s) > 0` guard when the
    separator turns out to be empty. PosEx in strutils always agreed with FPC
    here; SysUtils.Pos did not (bug-b-pos-empty-substr-returns-1). }
  SayBool('pos-empty',      Pos('', 'abc') = 0);
  SayBool('pos-empty-var',  Pos(emptyStr, 'abc') = 0);
  SayBool('pos-both-empty', Pos('', '') = 0);
  SayBool('pos-found',      Pos('b', 'abc') = 2);
  SayBool('pos-absent',     Pos('z', 'abc') = 0);

  { StrUtils Ansi* family. The rows that matter are the ones nobody guesses
    right: Starts/Ends take (NEEDLE, haystack) while Contains takes
    (haystack, needle); an EMPTY needle is FALSE for Contains but TRUE for
    Starts/Ends; AnsiIndexStr answers -1 when absent; AddChar pads LEFT,
    AddCharR pads RIGHT, and neither truncates. All measured against
    FPC 3.2.2. }
  SayBool('ansi-contains',   AnsiContainsStr('hello', 'ell'));
  SayBool('ansi-contains-cs', not AnsiContainsStr('hello', 'ELL'));
  SayBool('ansi-contains-e', not AnsiContainsStr('hello', ''));
  SayBool('ansi-containstext', AnsiContainsText('hello', 'ELL'));
  SayBool('ansi-starts',     AnsiStartsStr('he', 'hello') and not AnsiStartsStr('HE', 'hello'));
  SayBool('ansi-starts-e',   AnsiStartsStr('', 'hello'));
  SayBool('ansi-starts-long', not AnsiStartsStr('hello!', 'hello'));
  SayBool('ansi-startstext', AnsiStartsText('HE', 'hello'));
  SayBool('ansi-ends',       AnsiEndsStr('lo', 'hello') and not AnsiEndsStr('LO', 'hello'));
  SayBool('ansi-ends-e',     AnsiEndsStr('', 'hello'));
  SayBool('ansi-endstext',   AnsiEndsText('LO', 'hello'));
  SayBool('ansi-index',      AnsiIndexStr('b', ['a', 'b', 'c']) = 1);
  SayBool('ansi-index-miss', AnsiIndexStr('z', ['a', 'b', 'c']) = -1);
  SayBool('ansi-index-cs',   AnsiIndexStr('B', ['a', 'b', 'c']) = -1);
  SayBool('ansi-indextext',  AnsiIndexText('B', ['a', 'b', 'c']) = 1);
  SayBool('ansi-replace',    AnsiReplaceStr('aaa', 'a', 'b') = 'bbb');
  SayBool('ansi-replace-cs', AnsiReplaceStr('aaa', 'A', 'b') = 'aaa');
  SayBool('ansi-replacetext', AnsiReplaceText('xAx', 'a', 'B') = 'xBx');
  SayBool('addchar',         AddChar('.', 'x', 5) = '....x');
  SayBool('addchar-nogrow',  AddChar('.', 'xxxxxxx', 5) = 'xxxxxxx');
  SayBool('addcharr',        AddCharR('.', 'x', 5) = 'x....');
  SayBool('addcharr-nogrow', AddCharR('.', 'xxxxxxx', 5) = 'xxxxxxx');
end.
