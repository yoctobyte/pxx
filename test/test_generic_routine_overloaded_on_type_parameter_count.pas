program test_generic_routine_overloaded_on_type_parameter_count;
{ One generic-routine NAME, declared at several type-parameter counts.

  The inline-use rewrite runs once per REGISTRATION and each registration
  speaks for one declaration, so while scanning for uses of `Wrap<T>` it also
  walks over every use of `Wrap<S, T>`. It used to refuse those outright:

      generic routine Wrap takes 1 type argument(s), not 2

  -- a false statement about a program that declares the two-parameter overload
  a few lines down. The count came from the registration doing the scanning,
  not from the program. Now the pass first asks whether ANY declaration of that
  name has the arity being asked for; if one does, the use belongs to a sibling
  and that sibling's own pass rewrites it, so this one stays quiet.

  .expected is fpc 3.2.2's own output.

  ROW C IS THE ORDER CONTROL. B is declared after the routine whose scan sees
  it, C before. A pre-pass that started at the scanning declaration's own
  position -- the obvious place, since that is where the use scan starts --
  would get B right and C wrong, and B alone cannot tell the two apart.

  ROW D IS THE GUARD WITH TEETH, and it lives in the _fail sibling
  test_generic_routine_arity_with_no_such_overload_fail.pas: an arity NOTHING
  declares must still be refused by name and count. Relaxing the check is what
  this test asserts, so the case that must stay refused is asserted too --
  otherwise the change reads as "deleted a diagnostic" and nothing here would
  notice. }
{$mode objfpc}

generic function Wrap<S, T>(a: S; b: T): T;
begin
  Result := b;
end;

generic function Wrap<T>(a: T): T;
begin
  Result := a + a;
end;

generic function Wrap<A, B, C>(x: A; y: B; z: C): C;
begin
  Result := z;
end;

begin
  { A -- one type parameter, the shape that always worked }
  WriteLn('one=', specialize Wrap<Integer>(21));

  { B -- two, declared BEFORE the one-parameter overload }
  WriteLn('two=', specialize Wrap<Integer, string>(1, 'ok'));

  { C -- three, declared AFTER it }
  WriteLn('three=', specialize Wrap<Integer, string, Boolean>(1, 'x', True));

  { E -- the same specialization twice: one routine, not two }
  WriteLn('again=', specialize Wrap<Integer, string>(2, 'yes'));
end.
