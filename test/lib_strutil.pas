program lib_strutil;
{ Smoke for the SysUtils string helpers added 2026-06-24: CompareStr/CompareText/
  SameText, TrimLeft/TrimRight, TryStrToInt, StringReplace, QuotedStr. }
uses sysutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var v: Integer;
begin
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

  SayBool('quoted', QuotedStr('it''s') = '''it''''s''');
end.
