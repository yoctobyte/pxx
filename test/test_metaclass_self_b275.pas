{ `Self` inside a CLASS method is the METACLASS -- and it must be the RUNTIME class.

  This is the semantics the whole thing turns on. FPC's idiom

      class function TAssert.Suite: TTest;
      begin
        Result := TTestSuite.Create(Self);
      end;

  only works because `TMyTest.Suite` reaches TAssert's body with Self = TMyTest. Making
  Self the statically-known class instead would compile, run, and silently build a suite
  for the wrong class -- so the class is passed as a real hidden argument (param 0 of
  every class method), exactly as an instance Self is.

  A class Self is a bare CLASS REFERENCE, so ClassName / InheritsFrom / passing it to a
  TClass parameter all work on it unchanged.

  Every way of reaching a class method has to carry the class:
    TDerived.M            the class named
    obj.M                 the instance's RUNTIME class (not the variable's static type)
    cr.M via TClass var   whatever cr holds
    bare sibling call     PROPAGATES the caller's Self -- the case that makes the idiom
                          compose, and the one a static Self would quietly break }
program test_metaclass_self_b275;

type
  TBase = class
    class function WhoAmI: string;
    class function Suite: string;
    class function Tagged(const pre: string): string;
  end;
  TDerived = class(TBase) end;
  TOther = class(TBase) end;

class function TBase.WhoAmI: string;
begin
  Result := Self.ClassName;         { Self IS the class }
end;

class function TBase.Suite: string;
begin
  { a BARE sibling class-method call must propagate Self, not reset it to TBase }
  Result := 'suite of ' + WhoAmI;
end;

class function TBase.Tagged(const pre: string): string;
begin
  Result := pre + WhoAmI;           { ...with arguments, too }
end;

var
  b: TBase;
  d: TDerived;
  cr: TClass;
begin
  { named class }
  writeln('named: ', TBase.WhoAmI, ' ', TDerived.WhoAmI, ' ', TOther.WhoAmI);

  { propagation through a bare sibling call }
  writeln('suite: ', TBase.Suite, ' | ', TDerived.Suite);
  writeln('tagged: ', TDerived.Tagged('>> '));

  { through an INSTANCE: the RUNTIME class, not the variable's static type }
  d := TDerived.Create;
  b := d;                            { static type TBase, runtime class TDerived }
  writeln('via instance: ', b.WhoAmI);
  writeln('via instance suite: ', b.Suite);

  { through a TClass VARIABLE }
  cr := TOther;
  writeln('via classref: ', cr.ClassName);

  { Self is a class reference: it answers the class-reference operations }
  writeln('inherits: ', TDerived.InheritsFrom(TBase), ' ', TBase.InheritsFrom(TDerived));
end.
