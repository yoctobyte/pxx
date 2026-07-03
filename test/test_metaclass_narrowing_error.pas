program test_metaclass_narrowing_error;

{ Assigning a metaclass variable with an ANCESTOR base to a metaclass of a
  descendant (compile-time narrowing) must be rejected. }

type
  TBase = class
  end;
  TChild = class(TBase)
  end;
  TBaseClass = class of TBase;
  TChildClass = class of TChild;

var
  bc: TBaseClass;
  cc: TChildClass;
begin
  bc := TChild;
  cc := bc;   { narrowing: compile error }
end.
