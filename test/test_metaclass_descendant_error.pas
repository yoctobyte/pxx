program test_metaclass_descendant_error;

{ Assigning a non-descendant class reference to a metaclass variable must be
  rejected at compile time. }

type
  TBase = class
  end;
  TOther = class
  end;
  TBaseClass = class of TBase;

var
  bc: TBaseClass;
begin
  bc := TOther;   { unrelated class: compile error }
end.
