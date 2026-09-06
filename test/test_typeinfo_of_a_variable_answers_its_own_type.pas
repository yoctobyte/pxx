{ FPC's TypeInfo takes a VARIABLE as readily as a type name, and
  `GetEnumName(TypeInfo(c), Ord(c))` is the spelling real code writes -- it is
  how tforin1 and every RTTI-over-a-value idiom is written. pxx resolved only
  NAMES OF TYPES, so a variable reached none of the type tables and every shape,
  an enum variable included, got `TypeInfo is not supported for type: c`.

  WHAT EACH ROW ASSERTS IS POINTER IDENTITY, not a kind number, and that is the
  point rather than a convenience. The claim under test is exactly "the variable
  form answers the same type as the type form", so comparing the two answers IS
  the claim; a kind number would be a weaker restatement that a wrong-but-
  plausible resolution could still satisfy (every ordinal alias reports kind 1).

  It also keeps this file honest about something it is NOT testing.
  `Ord(PTypeInfo(TypeInfo(TEnum))^.Kind)` is 3 under fpc and an ADDRESS under
  pxx, because TypeInfo does not return one shape of pointer here: an enum
  resolves to the enum's own RTTI blob -- which is what GetEnumName reads -- and
  every other type to a TTypeInfo header. That divergence is PRE-EXISTING and
  unrelated: it reproduces identically through the TYPE spelling, which this
  change does not touch. Asserting Kind would have imported it into a file about
  something else and made this test fail for a reason it does not own. The
  identity rows stay true under both compilers and would break the day the
  variable form started resolving somewhere different.

  The last row is the one that matters in practice: it is the tforin1 spelling,
  and it reads a name out of the RTTI rather than comparing two pointers, so it
  fails if the pointer is equal to the type form's and both are wrong. }
program test_typeinfo_of_a_variable_answers_its_own_type;
uses typinfo;
type
  TE   = (eA, eB, eC);
  TA1  = array of LongInt;
  TR   = record x: LongInt; end;
  TMyB = Byte;
var
  e: TE;
  a: TA1;
  r: TR;
  b: TMyB;
  i: LongInt;
begin
  Writeln('enum  same=', TypeInfo(e) = TypeInfo(TE));
  Writeln('dyn   same=', TypeInfo(a) = TypeInfo(TA1));
  Writeln('rec   same=', TypeInfo(r) = TypeInfo(TR));
  Writeln('alias same=', TypeInfo(b) = TypeInfo(TMyB));

  { A variable of a BUILTIN type has no named type to compare against, so this
    row reads the kind instead -- tkInteger is 1 and is portable here, unlike
    the enum case above. }
  Writeln('int   kind=', Ord(PTypeInfo(TypeInfo(i))^.Kind));

  { The shapes that DO carry a TTypeInfo header report it identically through
    both spellings; printed so a divergence names which shape moved. }
  Writeln('dyn   kind=', Ord(PTypeInfo(TypeInfo(a))^.Kind),
          ' rec kind=',  Ord(PTypeInfo(TypeInfo(r))^.Kind));

  e := eB;
  Writeln('enumname=', GetEnumName(TypeInfo(e), Ord(e)));
  e := eC;
  Writeln('enumname=', GetEnumName(TypeInfo(e), Ord(e)));
end.
