{ A DELIBERATE refusal, and a guard on the reason for it.

  fpc 3.2.2 accepts `array of const` in a procedural type under -Mobjfpc and
  -Mdelphi -- all four spellings, plain and `of object`, `const` and bare -- so
  by the usual rule pxx refusing it is a compat gap and the parse fix is three
  lines. That fix has now been written and REVERTED twice, and this file exists
  so the third person to write it finds out in twelve seconds instead of an
  hour.

  Making the declaration parse does not make the call work. An open-array
  LITERAL loses its hidden length through a procedural-type call --
  `c([7,8,9])` for `procedure(const A: array of Integer)` answers 263845145632,
  and the `of object` spelling answers 0, where fpc says 3 for both. That is a
  separate and larger defect with nothing to do with `array of const`, and
  since an `array of const` argument is a literal essentially always, parsing
  the declaration only converts this clean refusal into a silent wrong number.

  A clean refusal is the better failure while that stands. When
  bug-p-an-open-array-literal-loses-its-length-through-a-procedural-type-call
  lands, DELETE this file and replace it with the positive test -- do not edit
  it to expect success, because the whole content of the assertion is that we
  refuse rather than answer wrongly.

  bug-p-array-of-const-in-a-method-pointer-type-is-refused-and-parsing-it-is-the-trap }
{$mode objfpc}
program test_array_of_const_in_a_procedural_type_is_refused;
type
  TObjCb = procedure(const Args: array of const) of object;
var
  o: TObjCb;
begin
  o := nil;
  WriteLn('unreachable: the type declaration above must not compile');
end.
