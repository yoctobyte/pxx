program test_object_reference_error;

{ Member access on a bare class REFERENCE must be a compile error — the
  reference carries no instance, so there is no member to resolve; cast to a
  concrete class first.

  Was spelled `var o: object` until 2026-08-30, when that keyword was retired
  as a type reference and returned to its standard Object Pascal meaning
  (a value type). The diagnostic it guarded was never object-specific: it
  fires for any tyPointer whose element is tyClass with no class id, which is
  also how TClass is represented (pasparser_decl.inc:681). TClass is therefore
  the surviving construct that reaches it, and is what this test now pins.
  See decided/decide-revisit-object-types-rtl-generics-fired-the-trigger.

  NOTE `var o: TObject` does NOT reach this path: RegisterBuiltinTObject mints
  a real class row, so TObject member access is an ordinary class lookup and
  fails with "no such member" instead. }

type
  TA = class
    FX: Integer;
  end;

var
  c: TClass;
  a: TA;
begin
  a := TA.Create;
  c := TA;
  c.FX := 3;   { compile error: member access on a bare object reference }
end.
