{ `Low(s)` for a string VARIABLE has always answered 1 (and 0 for a frozen
  one). `Low(AnsiString)` -- the TYPE-NAME spelling of the same fact -- reported
  `undefined variable (AnsiString)`. One concept, two spellings, and only the
  spelling nobody had written a test for was missing; it is the string INDEX
  BASE, and the reason Delphi-compat code writes `for i := Low(s) to High(s)`.

  Now one shared `StringTypeBound`, asked at six sites: the keyword `string`,
  a builtin name, and a user alias -- each in both the EXPRESSION resolver and
  the CONSTANT one, which the source already documents as one concept in two
  places that must change together. The `const` rows here pin the second.

  HIGH OF A MANAGED STRING IS STILL REFUSED, ON PURPOSE, so it cannot be a row:
  fpc 3.2.2 answers `High(ShortString)` = 255 and `High(S10)` = 10 but REFUSES
  `High(AnsiString)` and `High(string)` with "type identifier not allowed
  here", because a managed string type has no upper bound. Measured for all
  seven spellings; the asymmetry is fpc's. The frozen High rows below are the
  half that does have an answer.

  THE VARIABLE ROWS ARE THE CONTROL. They go through a different path
  (ParseFactorCore's hlIsAnsi / hlIsFrozen arms) and always worked, so a
  regression in the shared bound helper moves the TYPE rows and leaves these
  standing -- and a regression in the string machinery generally moves both.

  `Low(string)` = 1 is the row that caught the first version of this fix, which
  passed tyString to the helper: `TypeIsFrozenString(tyString)` is TRUE (it is
  the legacy overloaded frozen kind), so the keyword answered 0 while
  `var s: string; Low(s)` answered 1. The keyword now resolves through
  ParseTypeKind, exactly as a declaration does. Keep this row beside its
  variable twin -- apart, neither one can show that disagreement.
  .expected is fpc 3.2.2's own output. }
program test_low_of_a_string_type_name_answers_like_the_variable;
{$mode delphi}
type
  S10 = string[10];
  TA  = AnsiString;
  TSS = ShortString;
const
  KL  = Low(AnsiString);
  KH  = High(S10);
  KSL = Low(ShortString);
  KKW = Low(string);
var
  s: string;
  a: AnsiString;
  ss: ShortString;
  t: S10;
begin
  s := 'abcde'; a := 'abcde'; ss := 'abc'; t := 'abc';

  WriteLn('type  string       ', Low(string));
  WriteLn('type  ansistring   ', Low(AnsiString));
  WriteLn('type  unicodestring', Low(UnicodeString));
  WriteLn('type  widestring   ', Low(WideString));
  WriteLn('type  utf8string   ', Low(UTF8String));
  WriteLn('type  rawbytestring', Low(RawByteString));
  WriteLn('type  shortstring  ', Low(ShortString));
  WriteLn('high  shortstring  ', High(ShortString));

  WriteLn('alias ansi         ', Low(TA));
  WriteLn('alias short lo/hi  ', Low(TSS), ' ', High(TSS));
  WriteLn('alias s10   lo/hi  ', Low(S10), ' ', High(S10));

  WriteLn('const KL KH KSL KKW', KL, ' ', KH, ' ', KSL, ' ', KKW);

  { the controls: the VARIABLE spelling of the same question }
  WriteLn('var   string       ', Low(s));
  WriteLn('var   ansistring   ', Low(a));
  WriteLn('var   shortstring  ', Low(ss), ' ', High(ss));
  WriteLn('var   s10          ', Low(t));

  WriteLn('STRING BOUNDS OK');
end.
