program test_one_char_literal_not_a_typed_pointer_fails;
{ The SIBLING of test_string_literal_not_a_typed_pointer_fails, and the reason
  it is a separate file: a ONE-CHARACTER string literal is tagged tyChar, not
  tyString, so the first spelling of that guard walked straight past it. The
  multi-character call was correctly refused while the one-character call
  compiled and segfaulted -- a guard whose verdict depended on the LENGTH of an
  identifier.

  Found for real, not by probing: `SetEnumProp(t, 'C', 'clGreen')` against
  lib/rtl/typinfo.pas's new by-name arms died where `SetEnumProp(t, 'Col',
  'clGreen')` lived.

  fpc 3.2.2 -Mdelphi refuses this line too: "Incompatible type for arg no. 1:
  Got "Char", expected "PRec"".

  Char -> PChar stays ACCEPTED and is asserted in
  test_string_literal_not_a_typed_pointer_ok.pas ('pchar from char', 'pchar
  assign'); this refusal is only for a pointee the char is not.
  bug-p-a-string-literal-binds-to-any-typed-pointer-parameter-and-segfaults }
type
  TRec = record a, b: Integer; end;
  PRec = ^TRec;
function Take(p: PRec): Integer;
begin
  if p = nil then Take := -1 else Take := p^.a;
end;
begin
  writeln(Take('C'));
end.
