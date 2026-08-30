{ A nested `specialize X<T>` that appears ONLY inside a generic's METHOD BODY.

  The prerequisite scan in ParseSpecialization swept the class body
  (Templates[ti]) and nothing else. Method bodies are buffered separately by
  BufferGenericMethod, so a nested specialization living only in a method was
  never registered: no alias declaration was emitted, the collapse found the
  name unknown, and the literal word `specialize` survived into the token
  stream -- reported as `undefined variable (specialize)`, which names a
  keyword and points nowhere useful.

  That is exactly where rtl-generics puts it: `TComparer<T>.Default` inside a
  class constructor body and nowhere else. The specialization has to be by the
  ENCLOSING generic's type parameter -- with a concrete argument it always
  resolved, which is what kept this narrow enough to survive.

  Two DIFFERENT specializations of the enclosing generic are exercised, so the
  test would catch a fix that bound the first one's argument everywhere.

  NOT covered here, deliberately: specializing the SAME template on BOTH
  enclosing parameters in one template
  (`specialize TCmp<T>.Size * 100 + specialize TCmp<U>.Size`). When this file
  was written that shape still failed, with `SizeOf: unknown type or variable`
  pointing at the inner template's own body, and it was kept out so a pass here
  would mean what it says.
  UPDATE 2026-08-30: it no longer fails -- fixed incidentally, already correct
  on pin v394. It now has its own file,
  test_generic_two_nested_specializations_of_one_template, and the exclusion
  above stands only as a description of scope, not of a live defect.

  Output verified against FPC 3.2.2.
  bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body }
program test_generic_nested_specialize_in_method_body;
{$mode objfpc}{$H+}
type
  generic TCmp<T> = class
    class function Size: LongInt; static;
  end;

  generic TOrd<T, U> = class
    class function Get: LongInt; static;
  end;

class function TCmp.Size: LongInt; begin Result := SizeOf(T); end;

{ specialized by the ENCLOSING generic's parameter, in a method body only }
class function TOrd.Get: LongInt;
begin
  Result := specialize TCmp<T>.Size;
end;

type
  TO1 = specialize TOrd<Int64, LongInt>;
  TO2 = specialize TOrd<LongInt, Byte>;
begin
  WriteLn(TO1.Get);
  WriteLn(TO2.Get);
end.
