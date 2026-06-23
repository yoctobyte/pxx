program test_metaclass_construct;

{ Metaclass-dispatched construction: `classRefVar.Create` allocates the DYNAMIC
  class the class-ref points at (instance size + VMT read from its RTTI blob) and
  runs its virtual constructor through the stamped VMT. The class-ref's dynamic
  type — not the static base — selects both the allocation and the ctor body. }

type
  TBase = class
    tag: Integer;
    constructor Create(n: Integer); virtual;
  end;
  TDer = class(TBase)
    constructor Create(n: Integer); override;
  end;
  TBaseClass = class of TBase;

constructor TBase.Create(n: Integer); begin tag := n; end;
constructor TDer.Create(n: Integer);  begin inherited Create(n); tag := n * 10; end;

var
  c: TBaseClass;
  o: TBase;
begin
  { Direct (compile-time class) still works. }
  o := TDer.Create(5);
  writeln(o.tag);            { 50 }

  { Metaclass holds a descendant -> allocates+constructs TDer. }
  c := TDer;
  o := c.Create(7);
  writeln(o.tag);            { 70 }

  { Metaclass holds the base -> allocates+constructs TBase (polymorphic). }
  c := TBase;
  o := c.Create(3);
  writeln(o.tag);            { 3 }
end.
