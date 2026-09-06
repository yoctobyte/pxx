program test_generic_routine_arity_with_no_such_overload_fail;
{ The POSITIVE CONTROL for the overload relaxation in
  test_generic_routine_overloaded_on_type_parameter_count.pas.

  That change stops the inline-use pass from refusing a `specialize` use whose
  arity does not match the registration doing the scanning -- because a sibling
  overload may declare that arity. This file declares Wrap at ONE arity only
  and asks for two, so nothing in the program can serve the use and the
  diagnostic must still name the routine and both counts. Without this row the
  relaxation reads as "deleted a diagnostic" and the suite would not notice.

  fpc 3.2.2 refuses it too -- `Identifier not found "Wrap$2"`, its own mangled
  spelling of "Wrap at arity 2" -- which is why this is a _fail file and not a
  divergence. The two messages differ and that is deferred; what matters is
  that both compilers refuse. }
{$mode objfpc}

generic function Wrap<T>(a: T): T;
begin
  Result := a + a;
end;

begin
  WriteLn(specialize Wrap<Integer, string>(1, 'no such overload'));
end.
