program test_string_literal_not_a_typed_pointer_fails;
{ NEGATIVE half. A string literal must not bind to a pointer whose pointee is
  an unrelated type. TypesCompatible grants tyPointer <- tyString on purpose --
  a Pascal string marshals to a const char*, so a C binding needs no PChar()
  cast -- but that rule sees two KINDS and cannot see the pointee, so the
  literal used to land in a ^TRec slot and be dereferenced as one.

  fpc 3.2.2 -Mdelphi refuses the same line: "Incompatible type for arg no. 1:
  Got "Constant String", expected "PRec"".

  Found via lib/rtl/typinfo.pas, which has no by-name GetStrProp(Instance,
  PropName) while FPC's does -- so the FPC spelling every vendored consumer
  writes put a literal in the PPropInfo slot and segfaulted, instead of saying
  the overload does not exist.
  bug-p-a-string-literal-binds-to-any-typed-pointer-parameter-and-segfaults }
type
  TRec = record a, b: Integer; end;
  PRec = ^TRec;
function Take(p: PRec): Integer;
begin
  if p = nil then Take := -1 else Take := p^.a;
end;
begin
  writeln(Take('Name'));
end.
