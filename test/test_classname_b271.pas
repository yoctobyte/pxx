{ TObject.ClassName / TClass.ClassName. FPC declares ClassName on TObject in System,
  so it is reached with no `uses`.

  The point of this test is the classes below publish NOTHING. ClassName has to
  answer for ANY class, so every class now carries an RTTI header (rtti_emit.inc) --
  it used to be emitted only for classes with a published member, which made
  ClassName a coin flip: right on a class that happened to publish something, ''
  on one that did not.

  Both shapes are covered:
    instance         -> blob at [[inst+0] - 8]
    class reference  -> a TClass value IS the blob pointer
  including a TClass held in a VARIABLE and assigned at runtime, which is the case
  only the runtime blob can answer. This is fpcunit's GetN(C: TClass). }
program test_classname_b271;

type
  TBase = class
    x: Integer;
  end;
  TDerived = class(TBase)
    y: Integer;
  end;
  { a class that DOES publish, to prove the two paths still agree }
  TPub = class
  published
    procedure Go;
  end;

procedure TPub.Go;
begin
end;

{ verbatim from fpcunit.pp }
function GetN(C: TClass): string;
begin
  if C = nil then
    Result := '<NIL>'
  else
    Result := C.ClassName;
end;

var
  b: TBase;
  d: TDerived;
  p: TPub;
  cr: TClass;
begin
  b := TBase.Create;
  d := TDerived.Create;
  p := TPub.Create;

  writeln('inst: ', b.ClassName, ' ', d.ClassName, ' ', p.ClassName);
  writeln('parens: ', b.ClassName());
  writeln('classref: ', GetN(TBase), ' ', GetN(TDerived), ' ', GetN(TPub));
  writeln('nil: ', GetN(nil));

  { a class reference chosen at RUNTIME }
  cr := TDerived;
  writeln('var: ', GetN(cr));
  cr := TBase;
  writeln('var2: ', GetN(cr));

  { an instance's name is its OWN class, not the static type of the variable }
  b := d;
  writeln('dynamic: ', b.ClassName);
end.
