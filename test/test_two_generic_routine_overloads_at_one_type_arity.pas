program test_two_generic_routine_overloads_at_one_type_arity;
{ Two generic routines sharing a NAME and a TYPE-PARAMETER COUNT and differing
  only in how many VALUE parameters they take. `Add<T>(a, b: T)` and
  `Add<T>(a: T)` are ordinary overloads in the source and both mangle to
  `Add_LongInt` once specialized -- so the mangled name has to name an overload
  SET, not one routine.

  It did not. The first template's sweep collapsed every `specialize Add<..>(`
  run in the stream to the identifier, the second template swept a stream in
  which its own uses no longer existed and emitted nothing, and the one-argument
  call was matched against the two-argument signature:
  `no overload of Add_LongInt matches these arguments`. A true statement about a
  program whose second overload had been dropped on the floor. tgenfunc8.pp is
  the corpus row and is burned by this.

  ROW 3 IS THE ONE THAT COSTS SOMETHING. `Early` uses `specialize Add<LongInt>`
  BEFORE the second overload is declared, where ordinary Pascal scope says only
  the first is a candidate -- so the first template must still sweep that far
  and emit for it, and the second template must NOT re-emit the body that use
  already produced. That is why the "already emitted" guard asks about the pair
  (name, parameter count) rather than about the name: with siblings, the name
  alone is exactly what cannot tell a body that is already there from a
  sibling's that is not.

  Rows 5-6 keep the ACROSS-arity case honest (`Add<S, T>` mangles to a distinct
  name and must be unaffected), and rows 7-8 are a single-template generic
  routine -- the overwhelmingly common shape, which must take the unchanged
  path. Differential against fpc 3.2.2. }
{$mode objfpc}

operator := (aOther: LongInt): String;
begin
  Str(aOther, Result);
end;

generic function Add<T>(aLeft, aRight: T): T;
begin Result := aLeft + aRight; end;

function Early: LongInt;
begin Result := specialize Add<LongInt>(1, 2); end;

generic function Add<S, T>(aLeft, aRight: S): T;
begin Result := aLeft + aRight; end;

generic function Add<T>(aLeft: T): T;
begin Result := aLeft + aLeft; end;

generic function Solo<T>(a: T): T;
begin Result := a; end;

begin
  WriteLn('1 ', specialize Add<LongInt>(4, 5));
  WriteLn('2 ', specialize Add<LongInt>(2));
  WriteLn('3 ', Early);
  WriteLn('4 ', specialize Add<String>('Te'), ' ', specialize Add<String>('a', 'b'));
  WriteLn('5 ', specialize Add<LongInt, String>(3, 8));
  WriteLn('6 ', specialize Add<LongInt, LongInt>(3, 8));
  WriteLn('7 ', specialize Solo<LongInt>(9));
  WriteLn('8 ', specialize Solo<String>('s'));
end.
