program test_forin_deref_ptr_array;
{$mode objfpc}{$H+}
{ `for x in p^` where p: ^array[0..N] of T.

  Every bare-name for-in arm requires the next token to be `do`, and `p` is
  followed by `^`, so a deref fell through to the general container-EXPRESSION
  path -- which handled a class with GetEnumerator and a dyn-array value and
  then gave up. That is why the refusal reads "not a generator, enum type, or
  iterable variable" and not ParseForInNodeAST's own message: it never reached
  that function.

  NOT materialised into a hidden local, which is the move the two arms above it
  make. For a dyn array that copies a handle and still aliases; a static pointee
  would be copied WHOLE, and the `aliased=` row below is what holds that
  decision in place -- it writes through the pointer BEFORE iterating and the
  sum must include the new value, which a private copy would miss.

  A NON-ZERO low bound is deliberately still refused, not handled: the loop
  builder synthesises a bare AN_INDEX that carries none of the tags the lvalue
  walk stamps on a hand-written `p^[i]`, so the low bound is not subtracted and
  `array[1..4]` printed shifted garbage. Refusing loudly is not a regression --
  it was refused before -- and it is asserted here so a later "fix" that admits
  the bound has to deal with the shift rather than ship it silently.
  bug-p-for-in-over-a-dereferenced-pointer-to-array-is-refused }
type
  TArr = array[0..3] of Integer;
  PArr = ^TArr;
  TStr = array[0..2] of AnsiString;
  PStr = ^TStr;
var
  a: TArr; p: PArr; x, s: Integer;
  sa: TStr; ps: PStr; w: AnsiString; acc: AnsiString;
begin
  a[0] := 0; a[1] := 10; a[2] := 20; a[3] := 30;
  p := @a;
  Write('direct=');
  for x in a do Write(x, ' ');
  WriteLn;
  Write('deref=');
  for x in p^ do Write(x, ' ');
  WriteLn;
  s := 0;
  for x in p^ do s := s + x;
  WriteLn('sum=', s);
  p^[2] := 99;
  s := 0;
  for x in p^ do s := s + x;
  WriteLn('aliased=', s);
  sa[0] := 'a'; sa[1] := 'b'; sa[2] := 'c';
  ps := @sa;
  acc := '';
  for w in ps^ do acc := acc + w;
  WriteLn('managed=', acc);
end.
