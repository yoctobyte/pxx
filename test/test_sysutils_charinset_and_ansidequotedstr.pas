{ Two SysUtils functions FPC has and pxx did not, added together because
  fcl-passrc needs both and they were found the same way: one behind the other,
  each invisible until the wall in front of it fell.

  CharInSet is `Ch in CSet` spelled as a function. TSysCharSet had been declared
  in lib/rtl/sysutils.pas for a while and its own comment already named this as
  "the parameter type of the CharInSet / character classification family" — the
  type was present, named after the function, and the function was absent. Both
  ANSWERS are asserted: a predicate that returns a constant, or one built over
  an empty set, passes any single-row test.

  AnsiDequotedStr strips one surrounding pair of quotes and collapses doubled
  quotes inside. ITS THREE NON-OBVIOUS CASES ARE FPC'S BEHAVIOUR, NOT CHOICES,
  and each has a row because each is a plausible place to differ:

    unquoted   a string that does not START with the quote comes back WHOLE and
               unexamined — `ab'cd` keeps its inner quote. An implementation
               that "strips quotes wherever it finds them" passes every other
               row here and fails this one.
    doubled    `'ab''c'` is `ab'c` — a doubled quote is an escape, not a
               terminator followed by a new string.
    unterminat an unterminated quote consumes to the end rather than raising or
               returning empty.

  The `empty` and `bare` rows are the degenerate inputs that crash a cursor
  written one character off. Every row is compared against fpc 3.2.2 -Mobjfpc
  rather than against my reading of its source.

  fcl-passrc pscanner.pp:559 and pparser.pp:4467.
  feature-b-sysutils-charinset, which covers both }
{$mode objfpc}
program test_sysutils_charinset_and_ansidequotedstr;
uses SysUtils;
var
  cs: TSysCharSet;
begin
  cs := ['A'..'Z', '_'];
  WriteLn('inset hit   = ', CharInSet('Q', cs));
  WriteLn('inset miss  = ', CharInSet('q', cs));
  WriteLn('inset edge  = ', CharInSet('_', cs), ' ', CharInSet('@', cs));
  WriteLn('inset empty = ', CharInSet('A', []));

  WriteLn('quoted      = [', AnsiDequotedStr('''hello''', ''''), ']');
  WriteLn('doubled     = [', AnsiDequotedStr('''ab''''c''', ''''), ']');
  WriteLn('unquoted    = [', AnsiDequotedStr('ab''cd', ''''), ']');
  WriteLn('unterminat  = [', AnsiDequotedStr('''abc', ''''), ']');
  WriteLn('empty       = [', AnsiDequotedStr('', ''''), ']');
  WriteLn('bare        = [', AnsiDequotedStr('''', ''''), ']');
  WriteLn('inner only  = [', AnsiDequotedStr('''''', ''''), ']');
  WriteLn('other quote = [', AnsiDequotedStr('"a""b"', '"'), ']');
end.
