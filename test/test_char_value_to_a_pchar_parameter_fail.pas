program test_char_value_to_a_pchar_parameter_fail;
{ The POSITIVE CONTROL for the refusal narrowed in
  test_char_argument_to_a_string_parameter.pas.

  That change scopes `a Char VALUE is not a PChar` to a POINTER parameter,
  because the predicate it was gated on also answers yes for a frozen-string
  parameter, where fpc accepts. The pointer case must still be refused: the
  ordinal is passed where a pointer is read, and the callee dereferences
  address 81. It COMPILED and SEGFAULTED before the refusal existed, which is
  the worst of the three outcomes available -- so a narrowing that quietly took
  the whole check with it would be invisible to every value assertion.

  fpc 3.2.2 refuses it too: `Incompatible type for arg no. 1: Got "Char",
  expected "PChar"`. }
var c: Char;
procedure Ptr(p: PChar); begin WriteLn(p); end;
begin
  c := 'Q';
  Ptr(c);
end.
