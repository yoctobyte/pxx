program test_metaclass_descendant;

{ Metaclass descendant enforcement: valid assignments (base, descendants,
  metaclass-var narrowing-free copies, nil) all compile and behave. }

type
  TBase = class
  published
    Tag: Integer;
  end;
  TChild = class(TBase)
  end;
  TGrand = class(TChild)
  end;
  TBaseClass = class of TBase;
  TChildClass = class of TChild;

var
  bc: TBaseClass;
  cc: TChildClass;
begin
  bc := TBase;    { the base itself }
  bc := TChild;   { a direct descendant }
  bc := TGrand;   { a deeper descendant }
  cc := TGrand;
  bc := cc;       { metaclass var whose base descends from TBase }
  bc := nil;
  if bc = nil then writeln('nil ok');
  bc := TChild;
  if bc <> nil then writeln('set ok');
  writeln('OK');
end.
